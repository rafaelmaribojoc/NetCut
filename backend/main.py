#!/usr/bin/env python3
"""
NetCut Parental Control Backend
===============================
A backend for network-based parental controls using ARP spoofing.
Runs on Windows (as Administrator) or Linux/Termux (with root).

Usage:
    Windows: Run as Administrator - python main.py
    Linux/Termux: sudo python main.py

Requirements:
    - Administrator/root privileges
    - Python 3.8+
    - Npcap (Windows) or libpcap (Linux)
"""

import threading
import time
import json
import os
import re
from datetime import datetime
from typing import Optional, Dict, List, Any
from dataclasses import dataclass, asdict
from contextlib import asynccontextmanager
import platform
import socket

# Use starlette directly for lighter weight
from starlette.applications import Starlette
from starlette.responses import JSONResponse
from starlette.routing import Route
from starlette.middleware import Middleware
from starlette.middleware.cors import CORSMiddleware

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
    "Bedtime": {"start": "21:00", "end": "06:00", "enabled": True},
}

# ============================================================================
# Data Classes (Pydantic-free)
# ============================================================================

@dataclass
class DeviceInfo:
    mac: str
    ip: str
    name: Optional[str] = None

    def to_dict(self) -> dict:
        return asdict(self)

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
        self.interface: str = self._detect_interface()
        self.presets = DEFAULT_PRESETS.copy()
        self.spoof_thread: Optional[threading.Thread] = None
        self.stop_spoofing = threading.Event()
        self.load_config()
    
    def _detect_interface(self) -> str:
        """Auto-detect the active network interface."""
        system = platform.system()
        try:
            if system == "Windows":
                # On Windows, Scapy uses interface names differently
                # Get list of interfaces and find the active one
                from scapy.arch.windows import get_windows_if_list
                interfaces = get_windows_if_list()
                for iface in interfaces:
                    # Look for WiFi or Ethernet with an IP
                    if iface.get('ips') and any(ip for ip in iface['ips'] if not ip.startswith('169.254')):
                        print(f"[*] Detected interface: {iface.get('name', 'Unknown')}")
                        return iface.get('name', '')
            else:
                # Linux/Android - try common interface names
                for iface in ['wlan0', 'eth0', 'en0', 'wlp2s0']:
                    try:
                        get_if_addr(iface)
                        return iface
                    except:
                        continue
        except Exception as e:
            print(f"[!] Interface detection error: {e}")
        
        # Fallback
        return "wlan0" if system != "Windows" else ""

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

    def get_status(self) -> dict:
        """Return current status as dictionary."""
        return {
            "is_blocking": self.is_blocking,
            "active_mode": self.active_mode,
            "target_mac": self.target_mac,
            "target_name": self.target_name,
            "presets": self.presets,
            "next_scheduled_action": get_next_scheduled_action()
        }

state = AppState()
scheduler = BackgroundScheduler()

# ============================================================================
# Network Utilities
# ============================================================================

def get_gateway_info() -> tuple:
    """Get gateway IP and MAC address."""
    try:
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
        network = ".".join(local_ip.split(".")[:-1]) + ".0/24"
        
        print(f"[*] Scanning network: {network}")
        
        arp_request = ARP(pdst=network)
        broadcast = Ether(dst="ff:ff:ff:ff:ff:ff")
        packet = broadcast / arp_request
        
        answered, _ = srp(packet, timeout=SCAN_TIMEOUT, verbose=False)
        
        for sent, received in answered:
            device = DeviceInfo(
                mac=received.hwsrc.upper(),
                ip=received.psrc,
                name=None
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
    
    target_ip = get_ip_from_mac(state.target_mac)
    if not target_ip:
        print(f"[!] Could not find IP for MAC {state.target_mac}")
        return
    
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
            packet = create_arp_packet(target_ip, state.target_mac, gateway_ip)
            sendp(packet, verbose=False, iface=state.interface)
            
            gateway_packet = create_arp_packet(gateway_ip, gateway_mac, target_ip)
            sendp(gateway_packet, verbose=False, iface=state.interface)
            
            time.sleep(1)
            
        except Exception as e:
            print(f"[!] Spoof error: {e}")
            time.sleep(2)
    
    print("[*] Stopping ARP spoof...")
    restore_arp(target_ip, state.target_mac, gateway_ip, gateway_mac)

def restore_arp(target_ip: str, target_mac: str, gateway_ip: str, gateway_mac: str):
    """Restore correct ARP entries to unblock target."""
    print("[*] Restoring ARP tables...")
    try:
        packet = Ether(dst=target_mac) / ARP(
            op=2,
            pdst=target_ip,
            hwdst=target_mac,
            psrc=gateway_ip,
            hwsrc=gateway_mac
        )
        sendp(packet, count=5, verbose=False, iface=state.interface)
        
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
        if state.active_mode == name:
            stop_blocking()
            state.active_mode = "Manual"

def setup_scheduler():
    """Configure APScheduler with preset schedules."""
    scheduler.remove_all_jobs()
    
    for preset_name, times in state.presets.items():
        if not times.get("enabled", True):
            continue
            
        start_time = times["start"]
        end_time = times["end"]
        
        start_hour, start_min = map(int, start_time.split(":"))
        end_hour, end_min = map(int, end_time.split(":"))
        
        scheduler.add_job(
            apply_preset,
            CronTrigger(hour=start_hour, minute=start_min),
            args=[preset_name, "start"],
            id=f"{preset_name}_start",
            replace_existing=True
        )
        
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
# Request Helpers
# ============================================================================

async def get_json_body(request) -> dict:
    """Parse JSON body from request."""
    try:
        return await request.json()
    except:
        return {}

def validate_time_format(time_str: str) -> bool:
    """Validate HH:MM time format."""
    return bool(re.match(r"^\d{2}:\d{2}$", time_str))

# ============================================================================
# API Endpoints (Starlette)
# ============================================================================

async def root(request):
    """Health check endpoint."""
    return JSONResponse({"status": "ok", "message": "NetCut Backend Running"})

async def get_status(request):
    """Get current blocking status and configuration."""
    return JSONResponse(state.get_status())

async def toggle_block(request):
    """Manual override: immediately block or unblock target."""
    body = await get_json_body(request)
    block = body.get("block", False)
    
    if not state.target_mac:
        return JSONResponse(
            {"error": "No target MAC address set"},
            status_code=400
        )
    
    state.active_mode = "Manual"
    
    if block:
        success = start_blocking()
    else:
        success = stop_blocking()
    
    if not success:
        return JSONResponse(
            {"error": "Failed to toggle block"},
            status_code=500
        )
    
    return JSONResponse({
        "success": True,
        "is_blocking": state.is_blocking,
        "message": f"Target {'BLOCKED' if state.is_blocking else 'UNBLOCKED'}"
    })

async def set_mode(request):
    """Activate a preset schedule mode."""
    body = await get_json_body(request)
    mode = body.get("mode", "")
    
    if mode not in state.presets and mode != "Manual":
        return JSONResponse(
            {"error": f"Unknown mode: {mode}"},
            status_code=400
        )
    
    if mode == "Manual":
        state.active_mode = "Manual"
        return JSONResponse({"success": True, "active_mode": mode})
    
    preset = state.presets[mode]
    now = datetime.now()
    current_time = now.strftime("%H:%M")
    
    start_time = preset["start"]
    end_time = preset["end"]
    
    if start_time > end_time:
        should_block = current_time >= start_time or current_time < end_time
    else:
        should_block = start_time <= current_time < end_time
    
    state.active_mode = mode
    
    if should_block:
        start_blocking()
    else:
        stop_blocking()
    
    return JSONResponse({
        "success": True,
        "active_mode": mode,
        "is_blocking": state.is_blocking,
        "message": f"Mode set to {mode}" + (" (currently blocking)" if should_block else "")
    })

async def update_schedule(request):
    """Update a preset schedule's times."""
    body = await get_json_body(request)
    preset = body.get("preset", "")
    start = body.get("start", "")
    end = body.get("end", "")
    enabled = body.get("enabled", True)
    
    if preset not in state.presets:
        return JSONResponse(
            {"error": f"Unknown preset: {preset}"},
            status_code=400
        )
    
    if not validate_time_format(start) or not validate_time_format(end):
        return JSONResponse(
            {"error": "Invalid time format. Use HH:MM"},
            status_code=400
        )
    
    state.presets[preset] = {
        "start": start,
        "end": end,
        "enabled": enabled
    }
    
    state.save_config()
    setup_scheduler()
    
    return JSONResponse({
        "success": True,
        "preset": preset,
        "schedule": state.presets[preset]
    })

async def get_devices(request):
    """Scan and list all devices on the network."""
    devices = scan_network()
    return JSONResponse([d.to_dict() for d in devices])

async def set_target(request):
    """Set the target device MAC address."""
    body = await get_json_body(request)
    mac = body.get("mac", "")
    name = body.get("name")
    
    if not mac:
        return JSONResponse(
            {"error": "MAC address required"},
            status_code=400
        )
    
    state.target_mac = mac.upper()
    state.target_name = name
    state.save_config()
    
    return JSONResponse({
        "success": True,
        "target_mac": state.target_mac,
        "target_name": state.target_name
    })

async def clear_target(request):
    """Clear the target device."""
    stop_blocking()
    state.target_mac = None
    state.target_name = None
    state.save_config()
    
    return JSONResponse({"success": True, "message": "Target cleared"})

async def get_presets(request):
    """Get all preset schedules."""
    return JSONResponse(state.presets)

# ============================================================================
# App Lifespan
# ============================================================================

@asynccontextmanager
async def lifespan(app):
    """Startup and shutdown events."""
    print("[*] NetCut Backend Starting...")
    setup_scheduler()
    scheduler.start()
    print("[*] Scheduler started")
    yield
    print("[*] Shutting down...")
    stop_blocking()
    scheduler.shutdown()

# ============================================================================
# Create Starlette App
# ============================================================================

routes = [
    Route("/", root, methods=["GET"]),
    Route("/status", get_status, methods=["GET"]),
    Route("/toggle_block", toggle_block, methods=["POST"]),
    Route("/set_mode", set_mode, methods=["POST"]),
    Route("/update_schedule", update_schedule, methods=["POST"]),
    Route("/devices", get_devices, methods=["GET"]),
    Route("/target", set_target, methods=["POST"]),
    Route("/target", clear_target, methods=["DELETE"]),
    Route("/presets", get_presets, methods=["GET"]),
]

middleware = [
    Middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
]

app = Starlette(
    debug=False,
    routes=routes,
    middleware=middleware,
    lifespan=lifespan
)

# ============================================================================
# Main Entry Point
# ============================================================================

if __name__ == "__main__":
    import uvicorn
    
    print("=" * 50)
    print("  NetCut Parental Control Backend")
    print("=" * 50)
    print()
    
    system = platform.system()
    if system == "Windows":
        print("[!] Run this script as ADMINISTRATOR!")
        print("[!] Make sure Npcap is installed: https://npcap.com/")
    else:
        print("[!] Run with: sudo python main.py")
    
    # Get local IP for display
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
        print(f"[*] Your PC's IP: {local_ip}")
        print(f"[*] Flutter app should connect to: http://{local_ip}:8000")
    except:
        pass
    
    print()
    
    # Bind to 0.0.0.0 so phone can connect over LAN
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8000,
        log_level="info"
    )
