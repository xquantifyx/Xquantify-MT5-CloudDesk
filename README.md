# Xquantify-MT5-CloudDesk

Run **MetaTrader 5 (MT5)** headlessly on Ubuntu servers/VPS using **Docker + Wine + LXDE + noVNC**.  
This simplified installer no longer needs broker presets — paste **any MT5 installer URL** or pass `--mt5-url`.

## 🚀 Quick Start

```bash
curl -O https://raw.githubusercontent.com/xquantifyx/Xquantify-MT5-CloudDesk/main/install_mt5_headless.sh
chmod +x install_mt5_headless.sh
sudo ./install_mt5_headless.sh
# Paste your MT5 installer URL when prompted (e.g. Bybit):
# https://download.metatrader.com/cdn/web/infra.capital.limited/mt5/bybit5setup.exe
```

### Non-interactive (CI / scripted)
```bash
sudo ./install_mt5_headless.sh --mt5-url "https://download.metatrader.com/cdn/web/infra.capital.limited/mt5/bybit5setup.exe"
```

## 🔑 Defaults
- Data dir: `~/mt5data`
- Downloads cache: `~/mt5downloads` (file: `mt5_Custom.exe`)
- noVNC: `http://<PUBLIC_IP>:6080`, VNC: `<PUBLIC_IP>:5901`

## 🧹 Uninstall / Cleanup

Remove container only:
```bash
sudo ./install_mt5_headless.sh --uninstall --yes
```

Full purge (container + data dir + downloads cache + image):
```bash
sudo ./install_mt5_headless.sh --purge-all --yes
```

Custom purge:
```bash
sudo ./install_mt5_headless.sh --uninstall --purge-data --purge-downloads --purge-images --yes
```

## 📌 Author & Contact
**Xquantify** · https://www.xquantify.com  
GitHub: https://github.com/xquantifyx/Xquantify-MT5-CloudDesk  
Telegram: https://t.me/xquantify
