# Xquantify-MT5-CloudDesk (Turbo)

**Fast & beginner-friendly** headless MT5 on Ubuntu with **Docker + Wine + LXDE + noVNC**.

### Quick Start
```bash
curl -O https://raw.githubusercontent.com/xquantifyx/Xquantify-MT5-CloudDesk/main/install_mt5_headless.sh
chmod +x install_mt5_headless.sh
sudo ./install_mt5_headless.sh
# Paste your MT5 installer URL when prompted (e.g. Bybit)
```

Non-interactive:
```bash
sudo ./install_mt5_headless.sh --mt5-url "https://download.metatrader.com/cdn/web/infra.capital.limited/mt5/bybit5setup.exe"
```

### Why it's fast
- Pulls a **prebuilt image** with Wine already installed (`ghcr.io/xquantifyx/mt5-clouddesk:latest`).
- If unavailable, **auto-falls back** to base image and installs Wine inside the container.
- Caches the MT5 installer at `~/mt5downloads/mt5_Custom.exe`.

### Debug install
```bash
sudo ./install_mt5_headless.sh --mt5-url "<YOUR_URL>" --debug-install
# Then visit http://<PUBLIC_IP>:6080 and double-click 'Install MT5 (Debug)'
```

### Uninstall
```bash
# Container only
sudo ./install_mt5_headless.sh --uninstall --yes

# Full purge (container + data + downloads + image)
sudo ./install_mt5_headless.sh --purge-all --yes
```

---

## Build & publish the prebuilt image (optional)
- Commit `Dockerfile.prebuilt` and the workflow below.
- GitHub Actions will build and push `ghcr.io/<your-org>/mt5-clouddesk:latest` on `main` changes.

`.github/workflows/build-ghcr.yml` is included in this pack.
