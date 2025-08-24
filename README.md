# Xquantify‑MT5‑CloudDesk

Deploy MetaTrader 5 on Ubuntu VPS using Docker + Wine + noVNC.  
Author: **Xquantify** — https://www.xquantify.com — Telegram: @xquantify

---

## ✨ Features
- Clean defaults under **`/opt/xquantify-mt5`** (`data`, `download`, `logs`)
- Choose installer via **`download/choices.txt`** or pass **`--mt5-url`**
- **`--choice <ID>`** and **`--choices-url`** supported
- Optional **`--broker <name>`** — cache installers per broker (`mt5_<name>.exe`)
- Pulls prebuilt image from GHCR (fast), falls back to base image + auto Wine install
- Auto-fixes Chrome apt GPG repo issues (host + container)
- Desktop shortcuts are **trusted** (no “execute text file?” dialog)
- MT5 **autostarts** on desktop login
- Detailed end‑of‑install **summary** (VNC URL/ports/password, dirs, container)

---

## 🚀 Quick Start (/opt layout)
```bash
curl -O https://raw.githubusercontent.com/xquantifyx/Xquantify-MT5-CloudDesk/main/install_mt5_headless.sh
chmod +x install_mt5_headless.sh
sudo BASE_DIR=/opt/xquantify-mt5 ./install_mt5_headless.sh
```

You’ll see an interactive menu sourced from `download/choices.txt`.  
Or skip the menu with a direct URL:

```bash
sudo ./install_mt5_headless.sh --mt5-url "https://download.metatrader.com/cdn/web/infra.capital.limited/mt5/bybit5setup.exe"
```

Pick by ID:
```bash
sudo ./install_mt5_headless.sh --choice bybit
```

Cache per broker (downloads to `/opt/xquantify-mt5/download/mt5_bybit.exe`):
```bash
sudo ./install_mt5_headless.sh --choice bybit --broker bybit
```

> **Access noVNC:** `http://<VPS_IP>:6080`  
> **VNC client:** `<VPS_IP>:5901` (password printed at the end)

---

## 📁 Directory Layout
```
/opt/xquantify-mt5
├── install_mt5_headless.sh
├── download/         # cached installers (*.exe), per broker if --broker used
├── data/             # persistent config & Wine prefix (volume)
└── logs/             # (reserved for future logging)
```

---

## 🧰 Uninstall / Cleanup
```bash
# Remove container only
sudo ./install_mt5_headless.sh --uninstall --yes

# Full purge: container + data + downloads + images
sudo ./install_mt5_headless.sh --purge-all --yes
```

---

## 🧩 `download/choices.txt` format
```
ID|Name|URL
```
Example (already included):
```
bybit|Bybit MT5 (official CDN)|https://download.metatrader.com/cdn/web/infra.capital.limited/mt5/bybit5setup.exe
backup|Backup MT5 (GitHub Release)|https://github.com/xquantifyx/Xquantify-MT5-CloudDesk/releases/download/v1.3.0/bybit5setup.exe
```
> Use **GitHub Releases** for large files and **avoid** `github.com/.../blob/...` links.  
> If you need a different list, pass `--choices-url "<raw-url>"`.

---

## 🔒 Firewall (optional)
```bash
sudo ufw allow 6080/tcp   # noVNC
sudo ufw allow 5901/tcp   # VNC
```

---

## 🩺 Troubleshooting
- **GPG/Chrome apt errors**: script will auto‑disable the invalid repo on host & container.
- **noVNC page opens but icon prompts “execute text file?”** → already handled by trusting `.desktop` via `gio`.
- **Direct GitHub link downloads HTML** → you used a `blob` link. Use **raw.githubusercontent.com** or a **Releases** link.

---

## 🙌 Credits
- Base desktop image: `dorowu/ubuntu-desktop-lxde-vnc:focal`
- Maintained by **Xquantify** · https://www.xquantify.com · Telegram: @xquantify · GitHub: xquantifyx/Xquantify-MT5-CloudDesk
