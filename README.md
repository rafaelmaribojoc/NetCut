# NetCut Parental Control System

A complete "All-in-One" parental control system that runs entirely on a rooted Android phone.

## Overview

- **Backend**: Python/FastAPI running in Termux with Scapy for ARP spoofing
- **Frontend**: Flutter app with beautiful Material 3 UI
- **Communication**: REST API on `http://127.0.0.1:8000`

## Project Structure

```
NetCut/
├── backend/
│   ├── main.py           # FastAPI backend with ARP spoofing
│   └── requirements.txt  # Python dependencies
├── frontend/
│   ├── lib/
│   │   └── main.dart     # Flutter app
│   ├── pubspec.yaml      # Flutter dependencies
│   └── analysis_options.yaml
└── README.md
```

## Prerequisites

- **Rooted Android device** (required for ARP spoofing)
- **Termux** with root access
- **Flutter SDK** for building the frontend

## Backend Setup (Termux)

### 1. Install Termux Packages

```bash
# Update packages
pkg update && pkg upgrade -y

# Install Python and root support
pkg install python tsu root-repo -y

# Optional: Install network tools for debugging
pkg install net-tools nmap -y
```

### 2. Install Python Dependencies

```bash
cd ~/NetCut/backend
pip install -r requirements.txt

# Or install manually:
pip install fastapi uvicorn scapy apscheduler pydantic netifaces
```

### 3. Run the Backend

```bash
# IMPORTANT: Must run with root privileges!
sudo python main.py

# Or using Termux's tsu:
tsu
python main.py
```

The backend will start on `http://127.0.0.1:8000`

## Frontend Setup (Flutter)

### 1. Build the App

```bash
cd frontend

# Get dependencies
flutter pub get

# Build APK
flutter build apk --release
```

### 2. Install on Device

```bash
# Install the APK
flutter install
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/status` | GET | Get current blocking status and configuration |
| `/toggle_block` | POST | Manual block/unblock (`{"block": true/false}`) |
| `/set_mode` | POST | Activate a preset (`{"mode": "Lunch"}`) |
| `/update_schedule` | POST | Modify preset times |
| `/devices` | GET | Scan network for devices |
| `/target` | POST | Set target MAC address |
| `/presets` | GET | Get all preset schedules |

## Default Presets

| Preset | Start | End |
|--------|-------|-----|
| Breakfast | 7:00 AM | 8:00 AM |
| Lunch | 12:00 PM | 1:00 PM |
| Dinner | 7:00 PM | 8:00 PM |
| Bedtime | 9:00 PM | 6:00 AM |

## How It Works

1. **Device Scanning**: The app scans your local network to discover connected devices
2. **Target Selection**: You select which device to control (your child's phone/tablet)
3. **ARP Spoofing**: When blocking, the backend uses ARP poisoning to intercept traffic
4. **Scheduled Control**: Presets automatically block internet during meal times and bedtime

## Troubleshooting

### Backend won't start
- Ensure you're running with `sudo` or `tsu`
- Check that all dependencies are installed
- Verify you're connected to WiFi

### Can't find devices
- Make sure you're on the same WiFi network as target devices
- Try running the network scan multiple times
- Check that the `wlan0` interface is correct (may be different on some devices)

### Block not working
- Verify root access is working: `sudo whoami` should return `root`
- Some routers have ARP protection enabled
- The target device may be using a VPN or static ARP entries

## Legal Notice

⚠️ **Warning**: ARP spoofing can be illegal if used on networks you don't own. This tool is intended **only for parental control on your own home network**. Use responsibly.

## License

MIT License - Use at your own risk.
