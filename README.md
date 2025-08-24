# Xquantify-MT5-CloudDesk (Sample Pack)

This pack includes:
- `install_mt5_headless.sh` — installer with GitHub **choices** + direct URL, debug mode, uninstall, robust apt handling, and detailed summary output.
- `download/choices.txt` — menu of installers for users to pick.
- This `README.md` — quick instructions.

## Quick Start
```bash
curl -O https://raw.githubusercontent.com/xquantifyx/Xquantify-MT5-CloudDesk/main/install_mt5_headless.sh
chmod +x install_mt5_headless.sh
sudo ./install_mt5_headless.sh
```

### Pick by ID
```bash
sudo ./install_mt5_headless.sh --choice bybit
```

### Use a direct URL
```bash
sudo ./install_mt5_headless.sh --mt5-url "https://download.metatrader.com/cdn/web/infra.capital.limited/mt5/bybit5setup.exe"
```

### Debug install (visible UI)
```bash
sudo ./install_mt5_headless.sh --mt5-url "<YOUR_URL>" --debug-install
# then visit http://<PUBLIC_IP>:6080 and double-click "Install MT5 (Debug)"
```

## Maintain the choices list
Edit `download/choices.txt` in the format:
```
ID|Name|URL
```
Avoid using `github.com/.../blob/...` links (that's HTML). Use **Releases** links or **raw.githubusercontent.com**.

## Uninstall
```bash
sudo ./install_mt5_headless.sh --uninstall --yes
# Or full purge
sudo ./install_mt5_headless.sh --purge-all --yes
```

**Author:** Xquantify · https://www.xquantify.com · GitHub: https://github.com/xquantifyx/Xquantify-MT5-CloudDesk · Telegram: https://t.me/xquantify
