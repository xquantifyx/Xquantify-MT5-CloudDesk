#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Xquantify-MT5-CloudDesk · Headless MT5 on Ubuntu (Docker + noVNC + Wine)
# Author: Xquantify (www.xquantify.com) · Telegram: @xquantify
# Adds: download cache for multiple brokers + broker presets (incl. Bybit)
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

# Broker & URL selection
BROKER="${BROKER:-metaquotes}"  # default preset
MT5_URL="${MT5_URL:-}"          # custom URL overrides broker preset

# Inside container
WINEPREFIX_DIR="/root/.wine"
MT5_EXE_WIN='C:\Program Files\MetaTrader 5\terminal64.exe'
MT5_SETUP_PATH="/root/mt5setup.exe"

show_help() {
cat <<EOF
Usage: sudo ./install_mt5_headless.sh [options]

Options:
  --http-port <port>         noVNC (browser) port (default: 6080)
  --vnc-port <port>          VNC client port (default: 5901)
  --vnc-pass <password>      VNC password (default: mt5VNCpass)
  --data-dir <dir>           Host data directory (default: ~/mt5data)
  --download-dir <dir>       Host download cache dir (default: ~/mt5downloads)
  --name <container>         Container name (default: mt5)
  --image <image>            Docker image (default: dorowu/ubuntu-desktop-lxde-vnc:focal)

  --broker <key>             Choose preset broker (default: metaquotes)
  --list-brokers             List available broker keys
  --mt5-url <url>            Custom installer URL (overrides --broker)

  -h, --help                 Show this help
EOF
}

# ---- Broker presets ----------------------------------------------------------
declare -A BROKER_URLS=(
  [metaquotes]="https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"
  [exness]="https://download.mql5.com/cdn/web/exness.technologies.ltd/mt5/mt5setup.exe"
  [icmarkets]="https://download.mql5.com/cdn/web/ic.markets/mt5/mt5setup.exe"
  [pepperstone]="https://download.mql5.com/cdn/web/pepperstone.group.limited/mt5/mt5setup.exe"
  [xm]="https://download.mql5.com/cdn/web/xm.global/mt5/mt5setup.exe"
  # NEW: Bybit
  [bybit]="https://download.metatrader.com/cdn/web/infra.capital.limited/mt5/bybit5setup.exe"
)

list_brokers() {
  echo "Available broker keys:"
  for k in "${!BROKER_URLS[@]}"; do echo "  - $k"; done | sort
}

resolve_url() {
  local url="$MT5_URL"
  if [[ -z "$url" ]]; then
    if [[ -n "${BROKER_URLS[$BROKER]:-}" ]]; then
      url="${BROKER_URLS[$BROKER]}"
    else
      echo "ERROR: Unknown broker '$BROKER' and no --mt5-url provided." >&2
      echo "Run with --list-brokers to see available keys." >&2
      exit 1
    fi
  fi
  echo "$url"
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

    --broker)       BROKER="$2"; shift 2;;
    --mt5-url)      MT5_URL="$2"; shift 2;;
    --list-brokers) list_brokers; exit 0;;

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
echo "BROKER:        $BROKER"
if [[ -n "$MT5_URL" ]]; then echo "(Custom URL overrides broker)"; fi
echo "====================================="

apt-get update -y >/dev/null 2>&1 || true
apt-get install -y curl dnsutils >/dev/null 2>&1 || true

FINAL_URL="$(resolve_url)"
FN_BROKER="${BROKER:-Custom}"
INSTALLER_NAME="mt5_${FN_BROKER}.exe"
[[ -n "$MT5_URL" ]] && INSTALLER_NAME="mt5_Custom.exe"

if ! command -v docker >/dev/null 2>&1; then
  echo "[+] Installing Docker..."
  apt-get update
  apt-get install -y docker.io
  systemctl enable docker
  systemctl start docker
else
  echo "[=] Docker found."
fi

mkdir -p "$DATA_DIR" "$DOWNLOAD_DIR"
echo "[=] Using data dir: $DATA_DIR"
echo "[=] Using download cache: $DOWNLOAD_DIR"

CACHED_PATH="${DOWNLOAD_DIR}/${INSTALLER_NAME}"
if [[ -f "$CACHED_PATH" ]]; then
  echo "[=] Installer found in cache: $CACHED_PATH"
else
  echo "[+] Downloading MT5 installer to cache..."
  curl -fL --retry 4 -o "$CACHED_PATH" "$FINAL_URL"
  echo "[=] Saved: $CACHED_PATH"
fi

echo "[+] Pulling image: $IMAGE"
docker pull "$IMAGE"

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "[!] Removing existing container: $CONTAINER_NAME"
  docker rm -f "$CONTAINER_NAME" || true
fi

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

sleep 5

echo "[+] Installing Wine inside container..."
docker exec -it "$CONTAINER_NAME" bash -lc "
set -e
dpkg --add-architecture i386
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  wine64 wine32 winbind cabextract wget xvfb xauth x11-xserver-utils winetricks \
  ca-certificates fonts-wqy-zenhei fonts-noto-cjk
"

echo "[=] Initializing Wine prefix..."
docker exec -it "$CONTAINER_NAME" bash -lc "
set -e
mkdir -p /config/wineprefix
ln -sfn /config/wineprefix $WINEPREFIX_DIR || true
WINEPREFIX=$WINEPREFIX_DIR winecfg >/dev/null 2>&1 || true
"

echo "[=] Installing MT5 from cached installer: $INSTALLER_NAME"
docker exec -it "$CONTAINER_NAME" bash -lc "
set -e
cp '/downloads/${INSTALLER_NAME}' '$MT5_SETUP_PATH'
WINEPREFIX=$WINEPREFIX_DIR wine '$MT5_SETUP_PATH' /silent || true
"

echo "[=] Creating launcher & autostart..."
docker exec -it "$CONTAINER_NAME" bash -lc "
set -e
cat >/usr/local/bin/mt5 <<'EOF'
#!/usr/bin/env bash
export WINEPREFIX='$WINEPREFIX_DIR'
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
grep -q '/usr/local/bin/mt5' \$AUTOSTART 2>/dev/null || echo '@/usr/local/bin/mt5' >> \$AUTOSTART
"

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
  end
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
echo "Broker:     $BROKER"
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
