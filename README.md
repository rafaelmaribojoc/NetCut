# NetCut Parental Control System

A complete "All-in-One" parental control system with a Python backend and Flutter mobile app.

## Overview

- **Backend**: Python/Starlette running on Windows PC (as Administrator)
- **Frontend**: Flutter app on Android phone
- **Communication**: REST API over your local WiFi network

## Project Structure

```
NetCut/
├── backend/
│   ├── main.py           # Starlette backend with ARP spoofing
│   └── requirements.txt  # Python dependencies
├── frontend/
│   ├── lib/
│   │   └── main.dart     # Flutter app
│   ├── pubspec.yaml      # Flutter dependencies
│   └── analysis_options.yaml
└── README.md
```

## Prerequisites

- **Windows PC** connected to your home WiFi
- **Npcap** installed (required for packet capture): https://npcap.com/
- **Python 3.8+** on your PC
- **Flutter SDK** for building the mobile app

## Backend Setup (Windows PC)

### 1. Install Npcap

Download and install Npcap from https://npcap.com/

During installation, check the option **"Install Npcap in WinPcap API-compatible Mode"**.

### 2. Install Python Dependencies

```bash
cd backend
pip install -r requirements.txt

# Or install manually:
pip install starlette uvicorn scapy apscheduler
```

### 3. Run the Backend (as Administrator!)

**Important**: Right-click Command Prompt → **Run as Administrator**

```bash
cd backend
python main.py
```

The terminal will show your PC's IP address, like:
```
[*] Your PC's IP: 192.168.1.100
[*] Flutter app should connect to: http://192.168.1.100:8000
```

## Frontend Setup (Flutter)

### 1. Build the App

```bash
cd frontend

# Get dependencies
flutter pub get

# Build APK
flutter build apk --release
```

### 2. Install on Your Phone

```bash
flutter install
```

### 3. Configure the Server URL

1. Open the app on your phone
2. Tap the cloud icon (⛅/🔧) in the top-right corner
3. Enter your PC's IP address (e.g., `http://192.168.1.100:8000`)
4. Tap **Connect**

The cloud icon will turn green ✅ when connected.

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

1. **Backend runs on your PC** - Must be on the same WiFi as target devices
2. **Device Scanning** - The app discovers devices on your network
3. **Target Selection** - Select which device to control (your child's phone/tablet)
4. **ARP Spoofing** - When blocking, the backend uses ARP poisoning to intercept traffic
5. **Scheduled Control** - Presets automatically block internet during specified times

## Troubleshooting

### Backend won't start
- Make sure you're running Command Prompt **as Administrator**
- Verify Npcap is installed
- Check that Python and dependencies are installed correctly

### "No module named scapy"
```bash
pip install scapy
```

### Can't find devices
- Make sure your PC is on the same WiFi network as target devices
- Try running the network scan multiple times
- Check Windows Firewall isn't blocking the app

### Flutter app can't connect
- Verify your PC's IP address is correct
- Make sure both devices are on the same WiFi network
- Check Windows Firewall allows inbound connections on port 8000
- Try temporarily disabling Windows Firewall for testing

### Block not working
- Verify you're running as Administrator
- Some routers have ARP protection enabled
- The target device may be using a VPN or static ARP entries

## Firewall Configuration

If the app can't connect, you may need to allow port 8000 in Windows Firewall:

```powershell
# Run as Administrator
netsh advfirewall firewall add rule name="NetCut Backend" dir=in action=allow protocol=tcp localport=8000
```

## Legal Notice

⚠️ **Warning**: ARP spoofing can be illegal if used on networks you don't own. This tool is intended **only for parental control on your own home network**. Use responsibly.

## License

MIT License - Use at your own risk.
