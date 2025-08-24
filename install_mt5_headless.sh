#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Xquantify-MT5-CloudDesk (Turbo) · Headless MT5 on Ubuntu (Docker + noVNC + Wine)
# Author: Xquantify (www.xquantify.com) · Telegram: @xquantify · GitHub: https://github.com/xquantifyx/Xquantify-MT5-CloudDesk
# Fast & beginner friendly:
#   - Pulls prebuilt image with Wine preinstalled (if available), else falls back automatically
#   - Interactive MT5 URL prompt (or pass --mt5-url)
#   - Auto-disable broken apt sources (e.g., Chrome GPG key issues)
#   - Full uninstall flags
#   - Optional --debug-install to see the installer UI
# -----------------------------------------------------------------------------
set -euo pipefail

# ===== Defaults you can override =============================================
HTTP_PORT="${HTTP_PORT:-6080}"         # noVNC (browser) port
VNC_PORT="${VNC_PORT:-5901}"           # VNC client port
VNC_PASS="${VNC_PASS:-mt5VNCpass}"     # VNC password (auto-generated if default)
DATA_DIR="${DATA_DIR:-$HOME/mt5data}"  # Persistent data dir on host
DOWNLOAD_DIR="${DOWNLOAD_DIR:-$HOME/mt5downloads}"  # cache installers
CONTAINER_NAME="${CONTAINER_NAME:-mt5}"

# Try to use a prebuilt image first for speed. Fallback to base if not available.
PREFERRED_IMAGE="${PREFERRED_IMAGE:-ghcr.io/xquantifyx/mt5-clouddesk:latest}"
FALLBACK_IMAGE="${FALLBACK_IMAGE:-dorowu/ubuntu-desktop-lxde-vnc:focal}"
IMAGE="$FALLBACK_IMAGE"  # will be replaced if preferred pull works

MT5_URL="${MT5_URL:-}"                 # Custom URL or interactive prompt
DEBUG_INSTALL="${DEBUG_INSTALL:-0}"    # If 1: start desktop first and let user run installer visibly

# Uninstall flags
UNINSTALL="0"
PURGE_ALL="0"
PURGE_DATA="0"
PURGE_DOWNLOADS="0"
PURGE_IMAGES="0"
ASSUME_YES="0"

# Inside container
WINEPREFIX_DIR="/root/.wine"
MT5_SETUP_PATH="/root/mt5setup.exe"

show_help() {
cat <<EOF
Xquantify-MT5-CloudDesk (Turbo)
Run MT5 headlessly with Docker+Wine+noVNC. Paste your MT5 installer URL or pass --mt5-url.

Usage:
  sudo ./install_mt5_headless.sh [options]

Install options:
  --http-port <port>         noVNC (browser) port (default: 6080)
  --vnc-port <port>          VNC client port (default: 5901)
  --vnc-pass <password>      VNC password (default: random if not set)
  --data-dir <dir>           Host data directory (default: ~/mt5data)
  --download-dir <dir>       Host download cache dir (default: ~/mt5downloads)
  --name <container>         Container name (default: mt5)
  --image <image>            Force a specific Docker image (overrides auto)
  --mt5-url <url>            MT5 installer URL (if omitted, script will prompt)
  --debug-install            Start desktop first; create 'Install MT5 (Debug)' icon (no silent install)

Uninstall options:
  --uninstall                Stop & remove container only
  --purge-all                Uninstall + delete data dir + downloads cache + remove image
  --purge-data               Delete data dir (with --uninstall)
  --purge-downloads          Delete downloads cache (with --uninstall)
  --purge-images             Remove Docker image (with --uninstall)
  --yes                      Non-interactive (assume yes to prompts)
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
    --debug-install) DEBUG_INSTALL="1"; shift 1;;

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

# ===== Pretty header ==========================================================
echo "=== Xquantify · www.xquantify.com ==="
echo "HTTP(noVNC):   $HTTP_PORT"
echo "VNC:           $VNC_PORT"
echo "DATA_DIR:      $DATA_DIR"
echo "DOWNLOAD_DIR:  $DOWNLOAD_DIR"
echo "NAME:          $CONTAINER_NAME"
echo "PREFERRED_IMG: $PREFERRED_IMAGE"
echo "FALLBACK_IMG:  $FALLBACK_IMAGE"
if [[ "$UNINSTALL" == "1" || "$PURGE_ALL" == "1" ]]; then echo "MODE:          UNINSTALL"; fi
if [[ "$DEBUG_INSTALL" == "1" ]]; then echo "MODE:          DEBUG-INSTALL (visible installer)"; fi
echo "====================================="

# ===== Helpers ================================================================
confirm() {
  local msg="$1"
  if [[ "$ASSUME_YES" == "1" ]]; then return 0; fi
  read -r -p "$msg [y/N]: " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

pull_with_retry() {
  local img="$1"
  local tries=3
  local n=1
  while [[ $n -le $tries ]]; do
    if docker pull "$img" >/dev/null 2>&1; then return 0; fi
    echo "[!] Pull failed ($n/$tries) for $img, retrying..."
    sleep $((2*n))
    n=$((n+1))
  done
  return 1
}

# Randomize VNC password if default
if [[ "$VNC_PASS" == "mt5VNCpass" ]]; then
  VNC_PASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12 || true)"
  [[ -z "$VNC_PASS" ]] && VNC_PASS="Xq$(date +%s)"
  echo "[=] Generated VNC password: $VNC_PASS"
fi

# ===== Uninstall path =========================================================
if [[ "$UNINSTALL" == "1" || "$PURGE_ALL" == "1" ]]; then
  if [[ "$PURGE_ALL" == "1" ]]; then
    PURGE_DATA="1"; PURGE_DOWNLOADS="1"; PURGE_IMAGES="1"; ASSUME_YES="1"
  fi
  echo "[*] Uninstalling Xquantify-MT5-CloudDesk..."
  if command -v docker >/dev/null 2>&1; then
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
      echo "[+] Removing container: ${CONTAINER_NAME}"
      docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    fi
    if [[ "$PURGE_IMAGES" == "1" ]]; then
      if confirm "Remove Docker image ${PREFERRED_IMAGE} and ${FALLBACK_IMAGE}?"; then
        docker rmi "${PREFERRED_IMAGE}" >/dev/null 2>&1 || true
        docker rmi "${FALLBACK_IMAGE}"  >/dev/null 2>&1 || true
      fi
    fi
  fi
  if [[ "$PURGE_DATA" == "1" && -d "$DATA_DIR" ]]; then
    if confirm "Delete data dir ${DATA_DIR}?"; then rm -rf "$DATA_DIR"; fi
  fi
  if [[ "$PURGE_DOWNLOADS" == "1" && -d "$DOWNLOAD_DIR" ]]; then
    if confirm "Delete downloads cache ${DOWNLOAD_DIR}?"; then rm -rf "$DOWNLOAD_DIR"; fi
  fi
  echo "[DONE] Uninstall completed."
  exit 0
fi

# ===== Install path ===========================================================
echo "[*] Checking apt sources..."
if [ -f /etc/apt/sources.list.d/google-chrome.list ]; then
  if ! apt-get update -o Dir::Etc::sourcelist="sources.list.d/google-chrome.list" \
                     -o Dir::Etc::sourceparts="-" \
                     -o APT::Get::List-Cleanup="0" >/dev/null 2>&1; then
    echo "[!] Invalid Google Chrome apt source detected. Disabling..."
    mv /etc/apt/sources.list.d/google-chrome.list /etc/apt/sources.list.d/google-chrome.list.disabled || true
  fi
fi

apt-get update -y -qq || true
apt-get install -y -qq curl dnsutils >/dev/null 2>&1 || true

# Ask for URL if missing
if [[ -z "$MT5_URL" ]]; then
  echo "👉 Please paste your MT5 installer URL (e.g. Bybit):"
  echo "   https://download.metatrader.com/cdn/web/infra.capital.limited/mt5/bybit5setup.exe"
  read -r -p "URL: " MT5_URL
  if [[ -z "$MT5_URL" ]]; then echo "❌ Error: no URL provided."; exit 1; fi
fi
if ! echo "$MT5_URL" | grep -qiE '^https?://'; then
  echo "❌ Error: URL must start with http:// or https://"; exit 1
fi

# Ensure Docker installed
if ! command -v docker >/dev/null 2>&1; then
  echo "[+] Installing Docker..."
  apt-get update -qq && apt-get install -y -qq docker.io
  systemctl enable docker; systemctl start docker
else
  echo "[=] Docker found."
fi

# Prepare directories
mkdir -p "$DATA_DIR" "$DOWNLOAD_DIR"
echo "[=] Using data dir: $DATA_DIR"
echo "[=] Using download cache: $DOWNLOAD_DIR"

# Cache download
INSTALLER_NAME="mt5_Custom.exe"
CACHED_PATH="${DOWNLOAD_DIR}/${INSTALLER_NAME}"
if [[ -f "$CACHED_PATH" ]]; then
  echo "[=] Installer found in cache: $CACHED_PATH"
else
  echo "[+] Downloading MT5 installer to cache (with retries)..."
  n=1; until curl -fL --retry 5 --retry-all-errors -C - -o "$CACHED_PATH" "$MT5_URL"; do
    if [[ $n -ge 3 ]]; then echo "❌ Download failed."; exit 1; fi
    echo "[!] Retry download ($n/3)"; n=$((n+1)); sleep 2
  done
  echo "[=] Saved: $CACHED_PATH"
fi

# Choose the fastest image
if [[ -z "${IMAGE}" || "${IMAGE}" == "${FALLBACK_IMAGE}" ]]; then
  echo "[*] Trying to pull prebuilt image: ${PREFERRED_IMAGE}"
  if pull_with_retry "$PREFERRED_IMAGE"; then
    IMAGE="$PREFERRED_IMAGE"
  else
    echo "[!] Prebuilt image not available; using fallback: ${FALLBACK_IMAGE}"
    IMAGE="$FALLBACK_IMAGE"
  fi
fi

echo "[+] Using image: $IMAGE"
pull_with_retry "$IMAGE" || echo "[!] Proceeding with local cache if available."

# Remove old container if exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "[!] Removing existing container: $CONTAINER_NAME"
  docker rm -f "$CONTAINER_NAME" || true
fi

# Start container (mount data + downloads)
echo "[+] Starting container..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -p "${HTTP_PORT}:80" \
  -p "${VNC_PORT}:5900" \
  -e VNC_PASSWORD="${VNC_PASS}" \
  -e RESOLUTION="1600x900" \
  -v "${DATA_DIR}:/config" \
  -v "${DOWNLOAD_DIR}:/downloads:ro" \
  --shm-size=2g \
  "$IMAGE" >/dev/null

sleep 4

# If we're on the fallback image, we must install Wine inside the container
needs_wine=0
if [[ "$IMAGE" == "$FALLBACK_IMAGE" ]]; then needs_wine=1; fi

if [[ $needs_wine -eq 1 ]]; then
  echo "[+] Installing Wine inside container (fallback image)..."
  docker exec -it "$CONTAINER_NAME" bash -lc "
set -e
dpkg --add-architecture i386
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  wine64 wine32 winbind cabextract wget xvfb xauth x11-xserver-utils winetricks \
  ca-certificates fonts-wqy-zenhei fonts-noto-cjk
"
else
  echo "[=] Wine is already preinstalled in the prebuilt image."
fi

# Init Wine prefix
echo "[=] Initializing Wine prefix..."
docker exec -it "$CONTAINER_NAME" bash -lc "
set -e
mkdir -p /config/wineprefix
ln -sfn /config/wineprefix $WINEPREFIX_DIR || true
WINEPREFIX=$WINEPREFIX_DIR winecfg >/dev/null 2>&1 || true
"

if [[ "$DEBUG_INSTALL" == "1" ]]; then
  echo "[=] DEBUG mode: creating desktop shortcut to run the installer visibly."
  docker exec -it "$CONTAINER_NAME" bash -lc "
set -e
cp '/downloads/${INSTALLER_NAME}' '$MT5_SETUP_PATH'
cat >/usr/local/bin/mt5-install-debug <<'EOF'
#!/usr/bin/env bash
export WINEPREFIX='/root/.wine'
exec wine '/root/mt5setup.exe'
EOF
chmod +x /usr/local/bin/mt5-install-debug

mkdir -p /root/Desktop
cat >/root/Desktop/'Install MT5 (Debug).desktop' <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Install MT5 (Debug)
Comment=Run the MT5 installer visibly with Wine
Exec=/usr/local/bin/mt5-install-debug
Icon=system-software-install
Terminal=false
Categories=Utility;
EOF
chmod +x /root/Desktop/'Install MT5 (Debug).desktop'
"
else
  echo "[=] Installing MT5 silently..."
  docker exec -it "$CONTAINER_NAME" bash -lc "
set -e
cp '/downloads/${INSTALLER_NAME}' '$MT5_SETUP_PATH'
WINEPREFIX=$WINEPREFIX_DIR wine '$MT5_SETUP_PATH' /silent || true

cat >/usr/local/bin/mt5 <<'EOF'
#!/usr/bin/env bash
export WINEPREFIX='/root/.wine'
exec wine 'C:\\\\Program Files\\\\MetaTrader 5\\\\terminal64.exe'
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
fi

# Detect public IP & print URLs
detect_ip() {
  for svc in \
    "https://api.ipify.org" \
    "https://ifconfig.me" \
    "https://icanhazip.com" \
    "https://checkip.amazonaws.com"
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
echo "Image:      $IMAGE"
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
if [[ "$DEBUG_INSTALL" == "1" ]]; then
  echo
  echo "DEBUG mode: On the desktop, double-click 'Install MT5 (Debug)' to run the installer UI."
fi
echo
echo "If you use UFW, allow ports:"
echo "  sudo ufw allow ${HTTP_PORT}/tcp"
echo "  sudo ufw allow ${VNC_PORT}/tcp"
echo "-----------------------------------------------------------"
echo "[DONE] Ready."
