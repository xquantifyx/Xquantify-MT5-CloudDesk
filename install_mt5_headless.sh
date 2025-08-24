#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Xquantify-MT5-CloudDesk (Simple) · Headless MT5 on Ubuntu (Docker + noVNC + Wine)
# Author: Xquantify (www.xquantify.com) · Telegram: @xquantify · GitHub: https://github.com/xquantifyx/Xquantify-MT5-CloudDesk
# Simplified: no --broker presets. Accepts --mt5-url or prompts user to paste URL.
# Adds: Full uninstall flags.
# Caches installer under ~/mt5downloads/mt5_Custom.exe
# -----------------------------------------------------------------------------
set -euo pipefail

# ===== Defaults (overridable by flags) =======================================
HTTP_PORT="${HTTP_PORT:-6080}"         # noVNC (browser) port
VNC_PORT="${VNC_PORT:-5901}"           # VNC client port
VNC_PASS="${VNC_PASS:-mt5VNCpass}"     # VNC password
DATA_DIR="${DATA_DIR:-$HOME/mt5data}"  # Persistent data dir on host
DOWNLOAD_DIR="${DOWNLOAD_DIR:-$HOME/mt5downloads}"  # cache installers
CONTAINER_NAME="${CONTAINER_NAME:-mt5}"
IMAGE="${IMAGE:-dorowu/ubuntu-desktop-lxde-vnc:focal}"  # LXDE + noVNC + VNC
MT5_URL="${MT5_URL:-}"                 # Custom URL or interactive prompt

# Uninstall flags
UNINSTALL="0"
PURGE_ALL="0"
PURGE_DATA="0"
PURGE_DOWNLOADS="0"
PURGE_IMAGES="0"
ASSUME_YES="0"

# Inside container
WINEPREFIX_DIR="/root/.wine"
MT5_EXE_WIN='C:\\Program Files\\MetaTrader 5\\terminal64.exe'
MT5_SETUP_PATH="/root/mt5setup.exe"

show_help() {
cat <<EOF
Xquantify-MT5-CloudDesk (Simple)
Run MT5 headlessly with Docker+Wine+noVNC. Paste your MT5 installer URL or pass --mt5-url.

Usage:
  sudo ./install_mt5_headless_simple.sh [options]

Install options:
  --http-port <port>         noVNC (browser) port (default: 6080)
  --vnc-port <port>          VNC client port (default: 5901)
  --vnc-pass <password>      VNC password (default: mt5VNCpass)
  --data-dir <dir>           Host data directory (default: ~/mt5data)
  --download-dir <dir>       Host download cache dir (default: ~/mt5downloads)
  --name <container>         Container name (default: mt5)
  --image <image>            Docker image (default: dorowu/ubuntu-desktop-lxde-vnc:focal)
  --mt5-url <url>            MT5 installer URL (if omitted, script prompts)

Uninstall options:
  --uninstall                Stop & remove container only
  --purge-all                Uninstall + delete data dir + downloads cache + remove image
  --purge-data               Delete data dir (with --uninstall)
  --purge-downloads          Delete downloads cache (with --uninstall)
  --purge-images             Remove Docker image (with --uninstall)
  --yes                      Non-interactive (assume yes to prompts)

Examples:
  sudo ./install_mt5_headless_simple.sh
  sudo ./install_mt5_headless_simple.sh --mt5-url "https://download.metatrader.com/cdn/web/infra.capital.limited/mt5/bybit5setup.exe"
  sudo ./install_mt5_headless_simple.sh --uninstall --purge-all --yes
EOF
}

# ===== Parse flags ============================================================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --http-port)    HTTP_PORT="$2"; shift 2;;
    --vnc-port)     VNC_PORT="$2"; shift 2;;
    --vnc-pass)     VNC_PASS="$2"; shift 2;;
    --data-dir)     DATA_DIR="$2"; shift 2;;
    --download-dir) DOWNLOAD_DIR="$2"; shift 2;;
    --name)         CONTAINER_NAME="$2"; shift 2;;
    --image)        IMAGE="$2"; shift 2;;
    --mt5-url)      MT5_URL="$2"; shift 2;;

    --uninstall)        UNINSTALL="1"; shift 1;;
    --purge-all)        PURGE_ALL="1"; shift 1;;
    --purge-data)       PURGE_DATA="1"; shift 1;;
    --purge-downloads)  PURGE_DOWNLOADS="1"; shift 1;;
    --purge-images)     PURGE_IMAGES="1"; shift 1;;
    --yes)              ASSUME_YES="1"; shift 1;;

    -h|--help)      show_help; exit 0;;
    *) echo "Unknown argument: $1"; show_help; exit 1;;
  esac
done

echo "=== Xquantify · www.xquantify.com ==="
echo "HTTP(noVNC):   $HTTP_PORT"
echo "VNC:           $VNC_PORT"
echo "DATA_DIR:      $DATA_DIR"
echo "DOWNLOAD_DIR:  $DOWNLOAD_DIR"
echo "NAME:          $CONTAINER_NAME"
echo "IMAGE:         $IMAGE"
if [[ "$UNINSTALL" == "1" ]]; then echo "MODE:          UNINSTALL"; fi
echo "====================================="

# ===== Helper: prompt yes/no ================================================
confirm() {
  local msg="$1"
  if [[ "$ASSUME_YES" == "1" ]]; then
    return 0
  fi
  read -r -p "$msg [y/N]: " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

# ===== Uninstall path ========================================================
if [[ "$UNINSTALL" == "1" || "$PURGE_ALL" == "1" ]]; then
  # Decide purges
  if [[ "$PURGE_ALL" == "1" ]]; then
    PURGE_DATA="1"; PURGE_DOWNLOADS="1"; PURGE_IMAGES="1"; ASSUME_YES="${ASSUME_YES:-1}"
  fi

  echo "[*] Uninstalling Xquantify-MT5-CloudDesk..."
  # Stop & remove container
  if command -v docker >/dev/null 2>&1; then
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
      echo "[+] Removing container: ${CONTAINER_NAME}"
      docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    else
      echo "[=] Container not found: ${CONTAINER_NAME}"
    fi
    # Remove image
    if [[ "$PURGE_IMAGES" == "1" ]]; then
      if confirm "Remove Docker image ${IMAGE}?"; then
        docker rmi "${IMAGE}" >/dev/null 2>&1 || true
        echo "[=] Image removal attempted: ${IMAGE}"
      fi
    fi
  else
    echo "[=] Docker not installed; skipping container/image removal."
  fi

  # Purge data
  if [[ "$PURGE_DATA" == "1" ]]; then
    if [[ -d "$DATA_DIR" ]]; then
      if confirm "Delete data dir ${DATA_DIR}? This removes MT5 profiles/logins."; then
        rm -rf "$DATA_DIR"
        echo "[=] Deleted: $DATA_DIR"
      fi
    else
      echo "[=] Data dir not found: $DATA_DIR"
    fi
  fi

  # Purge downloads
  if [[ "$PURGE_DOWNLOADS" == "1" ]]; then
    if [[ -d "$DOWNLOAD_DIR" ]]; then
      if confirm "Delete downloads cache ${DOWNLOAD_DIR}?"; then
        rm -rf "$DOWNLOAD_DIR"
        echo "[=] Deleted: $DOWNLOAD_DIR"
      fi
    else
      echo "[=] Downloads dir not found: $DOWNLOAD_DIR"
    fi
  fi

  echo "[DONE] Uninstall completed."
  exit 0
fi

# ===== Install path ==========================================================
# Ensure tools
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y curl dnsutils >/dev/null 2>&1 || true

# Ask for URL if missing
if [[ -z "$MT5_URL" ]]; then
  echo "👉 Please paste your MT5 installer URL (e.g. Bybit):"
  echo "   https://download.metatrader.com/cdn/web/infra.capital.limited/mt5/bybit5setup.exe"
  read -r -p "URL: " MT5_URL
  if [[ -z "$MT5_URL" ]]; then
    echo "❌ Error: no URL provided. Exiting."
    exit 1
  fi
fi
# Basic URL sanity
if ! echo "$MT5_URL" | grep -qiE '^https?://'; then
  echo "❌ Error: URL must start with http:// or https://"
  exit 1
fi

# Ensure Docker
if ! command -v docker >/dev/null 2>&1; then
  echo "[+] Installing Docker..."
  apt-get update
  apt-get install -y docker.io
  systemctl enable docker
  systemctl start docker
else
  echo "[=] Docker found."
fi

# Prepare directories
mkdir -p "$DATA_DIR" "$DOWNLOAD_DIR"
echo "[=] Using data dir: $DATA_DIR"
echo "[=] Using download cache: $DOWNLOAD_DIR"

# Cache download (host)
INSTALLER_NAME="mt5_Custom.exe"
CACHED_PATH="${DOWNLOAD_DIR}/${INSTALLER_NAME}"
if [[ -f "$CACHED_PATH" ]]; then
  echo "[=] Installer found in cache: $CACHED_PATH"
else
  echo "[+] Downloading MT5 installer to cache..."
  curl -fL --retry 5 --retry-all-errors -o "$CACHED_PATH" "$MT5_URL"
  echo "[=] Saved: $CACHED_PATH"
fi

# Pull image
echo "[+] Pulling image: $IMAGE"
docker pull "$IMAGE"

# Remove old container if exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "[!] Removing existing container: $CONTAINER_NAME"
  docker rm -f "$CONTAINER_NAME" || true
fi

# Start container (mount data + downloads)
echo "[+] Starting container..."
docker run -d       --name "$CONTAINER_NAME"       --restart unless-stopped       -p "${HTTP_PORT}:80"       -p "${VNC_PORT}:5900"       -e VNC_PASSWORD="${VNC_PASS}"       -e RESOLUTION="1600x900"       -v "${DATA_DIR}:/config"       -v "${DOWNLOAD_DIR}:/downloads:ro"       --shm-size=2g       "$IMAGE" >/dev/null

sleep 5

# Install Wine inside container
echo "[+] Installing Wine inside container..."
docker exec -it "$CONTAINER_NAME" bash -lc "
set -e
dpkg --add-architecture i386
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends       wine64 wine32 winbind cabextract wget xvfb xauth x11-xserver-utils winetricks       ca-certificates fonts-wqy-zenhei fonts-noto-cjk
"

# Init Wine prefix
echo "[=] Initializing Wine prefix..."
docker exec -it "$CONTAINER_NAME" bash -lc "
set -e
mkdir -p /config/wineprefix
ln -sfn /config/wineprefix /root/.wine || true
WINEPREFIX=/root/.wine winecfg >/dev/null 2>&1 || true
"

# Install MT5 from cached installer
echo "[=] Installing MT5 from cached installer..."
docker exec -it "$CONTAINER_NAME" bash -lc "
set -e
cp '/downloads/${INSTALLER_NAME}' '$MT5_SETUP_PATH'
WINEPREFIX=/root/.wine wine '$MT5_SETUP_PATH' /silent || true
"

# Launcher, desktop icon, autostart
echo "[=] Creating launcher & autostart..."
docker exec -it "$CONTAINER_NAME" bash -lc "
set -e
cat >/usr/local/bin/mt5 <<'EOF'
#!/usr/bin/env bash
export WINEPREFIX='/root/.wine'
exec wine 'C:\\Program Files\\MetaTrader 5\\terminal64.exe'
EOF
chmod +x /usr/local/bin/mt5

mkdir -p /root/Desktop
cat >/root/Desktop/MetaTrader5.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=MetaTrader 5
Comment=Launch MetaTrader 5 (Wine)
Exec=/usr/local/bin/mt5
Icon=utilities-terminal
Terminal=false
Categories=Finance;
EOF
chmod +x /root/Desktop/MetaTrader5.desktop

mkdir -p /etc/xdg/lxsession/LXDE
AUTOSTART=/etc/xdg/lxsession/LXDE/autostart
grep -q '/usr/local/bin/mt5' $AUTOSTART 2>/dev/null || echo '@/usr/local/bin/mt5' >> $AUTOSTART
"

# Detect public IP & print URLs
detect_ip() {
  for svc in         "https://api.ipify.org"         "https://ifconfig.me"         "https://icanhazip.com"         "https://checkip.amazonaws.com"
  do
    ip="$(curl -fsS $svc || true)"
    ip="$(echo "$ip" | tr -d '[:space:]')"
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      echo "$ip"; return 0
    fi
  done
  ip="$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null || true)"
  ip="$(echo "$ip" | head -n1 | tr -d '[:space:]')"
  if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "$ip"; return 0
  fi
  echo ""
}

PUBLIC_IP="$(detect_ip || true)"

echo "-----------------------------------------------------------"
echo "Xquantify · www.xquantify.com"
echo "Container:  $CONTAINER_NAME"
echo "Data dir:   $DATA_DIR"
echo "Downloads:  $DOWNLOAD_DIR"
echo "VNC pass:   $VNC_PASS"
echo
if [[ -n "${PUBLIC_IP}" ]]; then
  echo "Open your browser to:"
  echo "  http://${PUBLIC_IP}:${HTTP_PORT}"
  echo
  echo "VNC client connect to:"
  echo "  ${PUBLIC_IP}:${VNC_PORT}"
else
  echo "Open your browser to: http://<YOUR_SERVER_IP>:${HTTP_PORT}"
  echo "(Public IP auto-detection failed. Substitute your server IP.)"
fi
echo
echo "If you use UFW, allow ports:"
echo "  sudo ufw allow ${HTTP_PORT}/tcp"
echo "  sudo ufw allow ${VNC_PORT}/tcp"
echo "-----------------------------------------------------------"
echo "[DONE] If silent MT5 install didn’t pop up, open the desktop (noVNC URL) and run MetaTrader 5 icon once."
