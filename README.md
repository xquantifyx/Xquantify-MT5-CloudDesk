# Xquantify-MT5-CloudDesk

Run **MetaTrader 5 (MT5)** headlessly on Ubuntu servers/VPS with **Docker + Wine + LXDE + noVNC**.  
Now includes a **download cache** and **broker presets** (MetaQuotes, Exness, IC Markets, Pepperstone, XM, **Bybit**).

---

## 🚀 Quick Start
```bash
curl -O https://raw.githubusercontent.com/xquantifyx/Xquantify-MT5-CloudDesk/main/install_mt5_headless.sh
chmod +x install_mt5_headless.sh
sudo ./install_mt5_headless.sh --vnc-pass "StrongVNCpass" --http-port 6080 --vnc-port 5901
```
The script **auto-detects your VPS public IP** and prints a ready-to-open URL like:
```
http://203.0.113.45:6080
```

---

## 🔧 Broker Presets & Download Cache

- Use a preset with `--broker <key>`; the installer is cached under `~/mt5downloads/mt5_<broker>.exe`.
- Or override with `--mt5-url <url>`.
- List all presets: `--list-brokers`

**Built-in brokers:**
```
metaquotes, exness, icmarkets, pepperstone, xm, bybit
```

**Examples:**
```bash
# Bybit
sudo ./install_mt5_headless.sh --broker bybit --name mt5_bybit   --data-dir ~/mt5data_bybit --http-port 6082 --vnc-port 5903 --vnc-pass BybitPass

# MetaQuotes generic + default ports
sudo ./install_mt5_headless.sh --broker metaquotes

# Custom URL (cached as mt5_Custom.exe)
sudo ./install_mt5_headless.sh --mt5-url "https://example.com/my_mt5.exe"
```

---

## 🐳 Ports
- `6080/tcp` → noVNC (browser desktop)
- `5901/tcp` → VNC client

If UFW is enabled:
```bash
sudo ufw allow 6080/tcp
sudo ufw allow 5901/tcp
```

---

## 🧰 Docker Compose (optional)
```yaml
version: "3.9"
services:
  mt5:
    image: dorowu/ubuntu-desktop-lxde-vnc:focal
    container_name: mt5
    restart: unless-stopped
    ports:
      - "6080:80"
      - "5901:5900"
    environment:
      - VNC_PASSWORD=mt5VNCpass
      - RESOLUTION=1600x900
    shm_size: "2g"
    volumes:
      - ./mt5data:/config
```

---

## 📌 Author & Contact
**Xquantify** · https://www.xquantify.com  
Telegram: https://t.me/xquantify
