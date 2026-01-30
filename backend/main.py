#!/usr/bin/env python3
"""
NetCut Parental Control Backend
===============================
A FastAPI backend for network-based parental controls using ARP spoofing.
Runs on Termux (rooted Android) with Scapy for network manipulation.

Usage:
    sudo python main.py

Requirements:
    - Rooted Android device
    - Termux with root-repo
    - Python 3.8+
"""

import threading
import time
import json
import os
from datetime import datetime, timedelta
from typing import Optional, Dict, List
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger

# Scapy imports - suppress warnings
import logging
logging.getLogger("scapy.runtime").setLevel(logging.ERROR)

from scapy.all import (
    ARP, Ether, sendp, srp, get_if_addr, conf, getmacbyip
)

# ============================================================================
# Configuration
# ============================================================================

CONFIG_FILE = "netcut_config.json"
SCAN_TIMEOUT = 3

# Default preset schedules (24-hour format)
DEFAULT_PRESETS = {
    "Breakfast": {"start": "07:00", "end": "08:00", "enabled": True},
    "Lunch": {"start": "12:00", "end": "13:00", "enabled": True},
    "Dinner": {"start": "19:00", "end": "20:00", "enabled": True},
    "Bedtime": {"start": "21:00", "end": "06:00", "enabled": True},  # Crosses midnight
}

# ============================================================================
# Pydantic Models
# ============================================================================

class DeviceInfo(BaseModel):
    mac: str
    ip: str
    name: Optional[str] = None

class ToggleBlockRequest(BaseModel):
    block: bool

class SetModeRequest(BaseModel):
    mode: str  # "Breakfast", "Lunch", "Dinner", "Bedtime", or "Manual"

class TargetRequest(BaseModel):
    mac: str
    name: Optional[str] = None

class ScheduleUpdate(BaseModel):
    preset: str
    start: str = Field(..., pattern=r"^\d{2}:\d{2}$")
    end: str = Field(..., pattern=r"^\d{2}:\d{2}$")
    enabled: bool = True

class StatusResponse(BaseModel):
    is_blocking: bool
    active_mode: Optional[str]
    target_mac: Optional[str]
    target_name: Optional[str]
    presets: Dict
    next_scheduled_action: Optional[str]

# ============================================================================
# Global State
# ============================================================================

class AppState:
    def __init__(self):
        self.is_blocking = False
        self.active_mode = "Manual"
        self.target_mac: Optional[str] = None
        self.target_name: Optional[str] = None
        self.gateway_ip: Optional[str] = None
        self.gateway_mac: Optional[str] = None
        self.interface: str = "wlan0"
        self.presets = DEFAULT_PRESETS.copy()
        self.spoof_thread: Optional[threading.Thread] = None
        self.stop_spoofing = threading.Event()
        self.load_config()

    def load_config(self):
        """Load configuration from file if exists."""
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, 'r') as f:
                    config = json.load(f)
                    self.presets = config.get("presets", DEFAULT_PRESETS)
                    self.target_mac = config.get("target_mac")
                    self.target_name = config.get("target_name")
            except Exception as e:
                print(f"[!] Failed to load config: {e}")

    def save_config(self):
        """Save configuration to file."""
        config = {
            "presets": self.presets,
            "target_mac": self.target_mac,
            "target_name": self.target_name,
        }
        try:
            with open(CONFIG_FILE, 'w') as f:
                json.dump(config, f, indent=2)
        except Exception as e:
            print(f"[!] Failed to save config: {e}")

state = AppState()
scheduler = BackgroundScheduler()

# ============================================================================
# Network Utilities
# ============================================================================

def get_gateway_info() -> tuple:
    """Get gateway IP and MAC address."""
    try:
        # Get default gateway IP
        gateway_ip = conf.route.route("0.0.0.0")[2]
        gateway_mac = getmacbyip(gateway_ip)
        return gateway_ip, gateway_mac
    except Exception as e:
        print(f"[!] Failed to get gateway info: {e}")
        return None, None

def get_local_ip() -> str:
    """Get local IP address."""
    try:
        return get_if_addr(state.interface)
    except:
        return "192.168.1.1"

def scan_network() -> List[DeviceInfo]:
    """Scan the local network for devices."""
    devices = []
    try:
        local_ip = get_local_ip()
        # Derive network range from local IP (assumes /24 subnet)
        network = ".".join(local_ip.split(".")[:-1]) + ".0/24"
        
        print(f"[*] Scanning network: {network}")
        
        # Create ARP request packet
        arp_request = ARP(pdst=network)
        broadcast = Ether(dst="ff:ff:ff:ff:ff:ff")
        packet = broadcast / arp_request
        
        # Send and receive
        answered, _ = srp(packet, timeout=SCAN_TIMEOUT, verbose=False)
        
        for sent, received in answered:
            device = DeviceInfo(
                mac=received.hwsrc.upper(),
                ip=received.psrc,
                name=None  # Could add hostname resolution here
            )
            devices.append(device)
            
        print(f"[*] Found {len(devices)} devices")
        
    except Exception as e:
        print(f"[!] Network scan failed: {e}")
    
    return devices

# ============================================================================
# ARP Spoofing Engine
# ============================================================================

def create_arp_packet(target_ip: str, target_mac: str, spoof_ip: str) -> Ether:
    """Create an ARP response packet for spoofing."""
    # op=2 means ARP reply
    # We tell the target that we are the gateway (spoof_ip)
    arp = ARP(
        op=2,
        pdst=target_ip,
        hwdst=target_mac,
        psrc=spoof_ip
    )
    return Ether(dst=target_mac) / arp

def get_ip_from_mac(target_mac: str) -> Optional[str]:
    """Get IP address from MAC by scanning network."""
    devices = scan_network()
    for device in devices:
        if device.mac.upper() == target_mac.upper():
            return device.ip
    return None

def spoof_target():
    """Continuously send spoofed ARP packets to disconnect target."""
    print(f"[*] Starting ARP spoof against {state.target_mac}")
    
    # Get target IP from MAC
    target_ip = get_ip_from_mac(state.target_mac)
    if not target_ip:
        print(f"[!] Could not find IP for MAC {state.target_mac}")
        return
    
    # Get gateway info
    gateway_ip, gateway_mac = get_gateway_info()
    if not gateway_ip or not gateway_mac:
        print("[!] Could not determine gateway")
        return
    
    state.gateway_ip = gateway_ip
    state.gateway_mac = gateway_mac
    
    print(f"[*] Target: {target_ip} ({state.target_mac})")
    print(f"[*] Gateway: {gateway_ip} ({gateway_mac})")
    
    while not state.stop_spoofing.is_set():
        try:
            # Spoof target: tell target that WE are the gateway
            # But we won't forward packets, effectively blocking internet
            packet = create_arp_packet(target_ip, state.target_mac, gateway_ip)
            sendp(packet, verbose=False, iface=state.interface)
            
            # Also optionally spoof gateway about target
            # This prevents the gateway from sending to target directly
            gateway_packet = create_arp_packet(gateway_ip, gateway_mac, target_ip)
            sendp(gateway_packet, verbose=False, iface=state.interface)
            
            time.sleep(1)  # Send every second
            
        except Exception as e:
            print(f"[!] Spoof error: {e}")
            time.sleep(2)
    
    print("[*] Stopping ARP spoof...")
    restore_arp(target_ip, state.target_mac, gateway_ip, gateway_mac)

def restore_arp(target_ip: str, target_mac: str, gateway_ip: str, gateway_mac: str):
    """Restore correct ARP entries to unblock target."""
    print("[*] Restoring ARP tables...")
    try:
        # Restore target's ARP cache
        packet = Ether(dst=target_mac) / ARP(
            op=2,
            pdst=target_ip,
            hwdst=target_mac,
            psrc=gateway_ip,
            hwsrc=gateway_mac
        )
        sendp(packet, count=5, verbose=False, iface=state.interface)
        
        # Restore gateway's ARP cache
        gateway_packet = Ether(dst=gateway_mac) / ARP(
            op=2,
            pdst=gateway_ip,
            hwdst=gateway_mac,
            psrc=target_ip,
            hwsrc=target_mac
        )
        sendp(gateway_packet, count=5, verbose=False, iface=state.interface)
        
        print("[*] ARP tables restored")
    except Exception as e:
        print(f"[!] Failed to restore ARP: {e}")

def start_blocking():
    """Start blocking the target device."""
    if not state.target_mac:
        print("[!] No target MAC set")
        return False
    
    if state.is_blocking:
        print("[*] Already blocking")
        return True
    
    state.stop_spoofing.clear()
    state.spoof_thread = threading.Thread(target=spoof_target, daemon=True)
    state.spoof_thread.start()
    state.is_blocking = True
    print(f"[+] BLOCKING {state.target_mac}")
    return True

def stop_blocking():
    """Stop blocking the target device."""
    if not state.is_blocking:
        print("[*] Not currently blocking")
        return True
    
    state.stop_spoofing.set()
    if state.spoof_thread:
        state.spoof_thread.join(timeout=5)
    state.is_blocking = False
    print(f"[-] UNBLOCKED {state.target_mac}")
    return True

# ============================================================================
# Scheduler Functions
# ============================================================================

def apply_preset(name: str, action: str):
    """Apply a preset schedule action (start or end blocking)."""
    print(f"[SCHEDULER] Preset '{name}' - Action: {action}")
    
    if action == "start":
        state.active_mode = name
        start_blocking()
    elif action == "end":
        if state.active_mode == name:  # Only stop if this preset started it
            stop_blocking()
            state.active_mode = "Manual"

def setup_scheduler():
    """Configure APScheduler with preset schedules."""
    # Remove all existing jobs
    scheduler.remove_all_jobs()
    
    for preset_name, times in state.presets.items():
        if not times.get("enabled", True):
            continue
            
        start_time = times["start"]
        end_time = times["end"]
        
        start_hour, start_min = map(int, start_time.split(":"))
        end_hour, end_min = map(int, end_time.split(":"))
        
        # Schedule start blocking
        scheduler.add_job(
            apply_preset,
            CronTrigger(hour=start_hour, minute=start_min),
            args=[preset_name, "start"],
            id=f"{preset_name}_start",
            replace_existing=True
        )
        
        # Schedule stop blocking
        scheduler.add_job(
            apply_preset,
            CronTrigger(hour=end_hour, minute=end_min),
            args=[preset_name, "end"],
            id=f"{preset_name}_end",
            replace_existing=True
        )
        
        print(f"[*] Scheduled {preset_name}: {start_time} - {end_time}")

def get_next_scheduled_action() -> Optional[str]:
    """Get the next scheduled action."""
    jobs = scheduler.get_jobs()
    if not jobs:
        return None
    
    next_job = min(jobs, key=lambda j: j.next_run_time)
    return f"{next_job.id} at {next_job.next_run_time.strftime('%H:%M')}"

# ============================================================================
# FastAPI App
# ============================================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown events."""
    print("[*] NetCut Backend Starting...")
    setup_scheduler()
    scheduler.start()
    print("[*] Scheduler started")
    yield
    print("[*] Shutting down...")
    stop_blocking()
    scheduler.shutdown()

app = FastAPI(
    title="NetCut Parental Control API",
    description="Network-based parental control using ARP spoofing",
    version="1.0.0",
    lifespan=lifespan
)

# Allow CORS for Flutter app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============================================================================
# API Endpoints
# ============================================================================

@app.get("/")
async def root():
    """Health check endpoint."""
    return {"status": "ok", "message": "NetCut Backend Running"}

@app.get("/status", response_model=StatusResponse)
async def get_status():
    """Get current blocking status and configuration."""
    return StatusResponse(
        is_blocking=state.is_blocking,
        active_mode=state.active_mode,
        target_mac=state.target_mac,
        target_name=state.target_name,
        presets=state.presets,
        next_scheduled_action=get_next_scheduled_action()
    )

@app.post("/toggle_block")
async def toggle_block(request: ToggleBlockRequest):
    """Manual override: immediately block or unblock target."""
    if not state.target_mac:
        raise HTTPException(status_code=400, detail="No target MAC address set")
    
    state.active_mode = "Manual"
    
    if request.block:
        success = start_blocking()
    else:
        success = stop_blocking()
    
    if not success:
        raise HTTPException(status_code=500, detail="Failed to toggle block")
    
    return {
        "success": True,
        "is_blocking": state.is_blocking,
        "message": f"Target {'BLOCKED' if state.is_blocking else 'UNBLOCKED'}"
    }

@app.post("/set_mode")
async def set_mode(request: SetModeRequest):
    """Activate a preset schedule mode."""
    mode = request.mode
    
    if mode not in state.presets and mode != "Manual":
        raise HTTPException(status_code=400, detail=f"Unknown mode: {mode}")
    
    if mode == "Manual":
        state.active_mode = "Manual"
        return {"success": True, "active_mode": mode}
    
    # Check if we should be blocking based on current time
    preset = state.presets[mode]
    now = datetime.now()
    current_time = now.strftime("%H:%M")
    
    start_time = preset["start"]
    end_time = preset["end"]
    
    # Handle overnight presets (e.g., Bedtime 21:00 - 06:00)
    if start_time > end_time:
        should_block = current_time >= start_time or current_time < end_time
    else:
        should_block = start_time <= current_time < end_time
    
    state.active_mode = mode
    
    if should_block:
        start_blocking()
    else:
        stop_blocking()
    
    return {
        "success": True,
        "active_mode": mode,
        "is_blocking": state.is_blocking,
        "message": f"Mode set to {mode}" + (" (currently blocking)" if should_block else "")
    }

@app.post("/update_schedule")
async def update_schedule(request: ScheduleUpdate):
    """Update a preset schedule's times."""
    if request.preset not in state.presets:
        raise HTTPException(status_code=400, detail=f"Unknown preset: {request.preset}")
    
    state.presets[request.preset] = {
        "start": request.start,
        "end": request.end,
        "enabled": request.enabled
    }
    
    state.save_config()
    setup_scheduler()
    
    return {
        "success": True,
        "preset": request.preset,
        "schedule": state.presets[request.preset]
    }

@app.get("/devices", response_model=List[DeviceInfo])
async def get_devices():
    """Scan and list all devices on the network."""
    devices = scan_network()
    return devices

@app.post("/target")
async def set_target(request: TargetRequest):
    """Set the target device MAC address."""
    state.target_mac = request.mac.upper()
    state.target_name = request.name
    state.save_config()
    
    return {
        "success": True,
        "target_mac": state.target_mac,
        "target_name": state.target_name
    }

@app.delete("/target")
async def clear_target():
    """Clear the target device."""
    stop_blocking()
    state.target_mac = None
    state.target_name = None
    state.save_config()
    
    return {"success": True, "message": "Target cleared"}

@app.get("/presets")
async def get_presets():
    """Get all preset schedules."""
    return state.presets

# ============================================================================
# Main Entry Point
# ============================================================================

if __name__ == "__main__":
    import uvicorn
    
    print("=" * 50)
    print("  NetCut Parental Control Backend")
    print("=" * 50)
    print()
    print("[!] This script requires ROOT privileges!")
    print("[*] Run with: sudo python main.py")
    print()
    
    # Start the server
    uvicorn.run(
        app,
        host="127.0.0.1",
        port=8000,
        log_level="info"
    )
