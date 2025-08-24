# Xquantify-MT5-CloudDesk — /opt layout

This build defaults everything under `/opt/xquantify-mt5` for a clean, portable setup.

## Structure
```
/opt/xquantify-mt5
├── install_mt5_headless.sh
├── download/      # cached installers
├── data/          # persistent data (container mount)
└── logs/          # optional logs
```

## One-liner
```bash
curl -O https://raw.githubusercontent.com/xquantifyx/Xquantify-MT5-CloudDesk/main/install_mt5_headless.sh
chmod +x install_mt5_headless.sh
sudo BASE_DIR=/opt/xquantify-mt5 ./install_mt5_headless.sh
```

## Choose installers
- Edit `download/choices.txt` in repo (ID|Name|URL), or pass `--mt5-url` directly.
