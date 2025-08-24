#!/usr/bin/env bash
# =============================================================================
# Xquantify-MT5-CloudDesk · Headless MT5 on Ubuntu (Docker + noVNC + Wine)
# Author : Xquantify (www.xquantify.com) · Telegram: @xquantify
# GitHub : https://github.com/xquantifyx/Xquantify-MT5-CloudDesk
# License: MIT
# =============================================================================
set -euo pipefail

# --- refuse running inside container ---
if [ -f /.dockerenv ] || grep -qa 'docker' /proc/1/cgroup 2>/dev/null; then
  echo "⚠ This installer must be run on the HOST, not inside the mt5 container."
  echo "   Exit this shell and run on the VPS:  sudo ./install_mt5_headless.sh ..."
  exit 1
fi

# ---------- Defaults ----------
BASE_DIR="${BASE_DIR:-/opt/xquantify-mt5}"
HTTP_PORT="${HTTP_PORT:-6080}"
VNC_PORT="${VNC_PORT:-5901}"
VNC_PASS="${VNC_PASS:-mt5VNCpass}"

DATA_DIR="${DATA_DIR:-${BASE_DIR}/data}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${BASE_DIR}/download}"
LOG_DIR="${LOG_DIR:-${BASE_DIR}/logs}"

CONTAINER_NAME="${CONTAINER_NAME:-mt5}"

PREFERRED_IMAGE="${PREFERRED_IMAGE:-ghcr.io/xquantifyx/mt5-clouddesk:latest}"
FALLBACK_IMAGE="${FALLBACK_IMAGE:-dorowu/ubuntu-desktop-lxde-vnc:focal}"
IMAGE="$FALLBACK_IMAGE"

MT5_URL="${MT5_URL:-}"
CHOICES_URL="${CHOICES_URL:-https://raw.githubusercontent.com/xquantifyx/Xquantify-MT5-CloudDesk/main/download/choices.txt}"
CHOICE_ID="${CHOICE_ID:-}"
BROKER="${BROKER:-}"
DEBUG_INSTALL="${DEBUG_INSTALL:-0}"

UNINSTALL="0"; PURGE_ALL="0"; PURGE_DATA="0"; PURGE_DOWNLOADS="0"; PURGE_IMAGES="0"; ASSUME_YES="0"

WINEPREFIX_DIR="/root/.wine"
MT5_SETUP_PATH="/root/mt5setup.exe"
DOCKERD_LOG="/var/log/dockerd.log"

show_help() {
cat <<'EOF'
Xquantify-MT5-CloudDesk (/opt layout)
Run MT5 headlessly with Docker + Wine + noVNC.

Usage:
  sudo ./install_mt5_headless.sh [options]

Install options:
  --http-port <port>         noVNC (browser) port (default: 6080)
  --vnc-port <port>          VNC client port (default: 5901)
  --vnc-pass <password>      VNC password (default: random if left as mt5VNCpass)
  --base-dir <dir>           Base dir (default: /opt/xquantify-mt5)
  --data-dir <dir>           Data dir (default: $BASE_DIR/data)
  --download-dir <dir>       Download cache dir (default: $BASE_DIR/download)
  --name <container>         Container name (default: mt5)
  --image <image>            Force a Docker image
  --mt5-url <url>            MT5 installer direct URL (skip choices menu)
  --choices-url <raw-url>    Raw URL to choices.txt (ID|Name|URL)
  --choice <ID>              Auto-select by ID from choices.txt
  --broker <name>            Tag cache file as mt5_<name>.exe
  --debug-install            Desktop first; create 'Install MT5 (Debug)' icon

Uninstall / cleanup:
  --uninstall                Stop & remove container (no file deletion)
  --purge-all                Uninstall + delete BASE_DIR (data, downloads, logs) + remove images
  --purge-data               Delete data dir (with --uninstall)
  --purge-downloads          Delete downloads dir (with --uninstall)
  --purge-images             Remove Docker images (with --uninstall)
  --yes                      Assume 'yes' to prompts
EOF
}

# parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --http-port)    HTTP_PORT="$2"; shift 2;;
    --vnc-port)     VNC_PORT="$2"; shift 2;;
    --vnc-pass)     VNC_PASS="$2"; shift 2;;
    --base-dir)     BASE_DIR="$2"; shift 2;;
    --data-dir)     DATA_DIR="$2"; shift 2;;
    --download-dir) DOWNLOAD_DIR="$2"; shift 2;;
    --name)         CONTAINER_NAME="$2"; shift 2;;
    --image)        IMAGE="$2"; shift 2;;
    --mt5-url)      MT5_URL="$2"; shift 2;;
    --choices-url)  CHOICES_URL="$2"; shift 2;;
    --choice)       CHOICE_ID="$2"; shift 2;;
    --broker)       BROKER="$2"; shift 2;;
    --debug-install) DEBUG_INSTALL="1"; shift 1;;

    --uninstall)        UNINSTALL="1"; shift 1;;
    --purge-all)        PURGE_ALL="1"; shift 1;;
    --purge-data)       PURGE_DATA="1"; shift 1;;
    --purge-downloads)  PURGE_DOWNLOADS="1"; shift 1;;
    --purge-images)     PURGE_IMAGES="1"; shift 1;;
    --yes)              ASSUME_YES="1"; shift 1;;

    -h|--help)          show_help; exit 0;;
    *) echo "Unknown argument: $1"; show_help; exit 1;;
  esac
done

mkdir -p "$BASE_DIR" "$DATA_DIR" "$DOWNLOAD_DIR" "$LOG_DIR"
chmod 755 "$BASE_DIR" || true

echo "=== Xquantify · www.xquantify.com ==="
echo "BASE_DIR:      $BASE_DIR"
echo "HTTP(noVNC):   $HTTP_PORT"
echo "VNC:           $VNC_PORT"
echo "DATA_DIR:      $DATA_DIR"
echo "DOWNLOAD_DIR:  $DOWNLOAD_DIR"
echo "NAME:          $CONTAINER_NAME"
echo "PREFERRED_IMG: $PREFERRED_IMAGE"
echo "FALLBACK_IMG:  $FALLBACK_IMAGE"
echo "CHOICES_URL:   $CHOICES_URL"
[[ "$DEBUG_INSTALL" == "1" ]] && echo "MODE:          DEBUG-INSTALL"
echo "====================================="

confirm() { local msg="$1"; [[ "$ASSUME_YES" == "1" ]] && return 0; read -r -p "$msg [y/N]: " a; [[ "${a,,}" == "y" || "${a,,}" == "yes" ]]; }

pull_with_retry() { local img="$1"; local n=1; while [[ $n -le 3 ]]; do docker pull "$img" >/dev/null 2>&1 && return 0; echo "[!] Pull failed ($n/3) for $img, retrying..."; sleep $((2*n)); n=$((n+1)); done; return 1; }

start_docker_daemon() {
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then echo "[=] Docker daemon already running."; return 0; fi
  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    echo "[*] Starting Docker via systemd..."; systemctl enable docker >/dev/null 2>&1 || true; systemctl start docker >/dev/null 2>&1 || true
  elif command -v service >/dev/null 2>&1; then
    echo "[*] Starting Docker via service..."; service docker start >/dev/null 2>&1 || true
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "[!] systemd/service not available; starting dockerd directly..."
    mkdir -p /var/run; nohup dockerd -H unix:///var/run/docker.sock >"$DOCKERD_LOG" 2>&1 &
    for i in $(seq 1 20); do docker info >/dev/null 2>&1 && break; sleep 0.5; done
  fi
  if ! docker info >/dev/null 2>&1; then echo "❌ Docker daemon could not be started. Check $DOCKERD_LOG"; return 1; fi
  echo "[=] Docker is ready."
}

# randomize VNC pass if default
if [[ "$VNC_PASS" == "mt5VNCpass" ]]; then VNC_PASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12 || true)"; [[ -z "$VNC_PASS" ]] && VNC_PASS="Xq$(date +%s)"; echo "[=] Generated VNC password: $VNC_PASS"; fi

# uninstall path
if [[ "$UNINSTALL" == "1" || "$PURGE_ALL" == "1" ]]; then
  [[ "$PURGE_ALL" == "1" ]] && PURGE_DATA="1" PURGE_DOWNLOADS="1" PURGE_IMAGES="1" ASSUME_YES="1"
  echo "[*] Uninstalling..."
  if command -v docker >/dev/null 2>&1; then
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    if [[ "$PURGE_IMAGES" == "1" ]]; then
      if confirm "Remove Docker images (preferred + fallback)?"; then
        docker rmi "${PREFERRED_IMAGE}" >/dev/null 2>&1 || true
        docker rmi "${FALLBACK_IMAGE}"  >/dev/null 2>&1 || true
      fi
    fi
  fi
  if [[ "$PURGE_ALL" == "1" ]]; then
    echo "[*] Removing entire $BASE_DIR ..."; rm -rf "$BASE_DIR" 2>/dev/null || true; rm -f "$DOCKERD_LOG" 2>/dev/null || true
  else
    [[ "$PURGE_DATA" == "1" && -d "$DATA_DIR" ]] && rm -rf "$DATA_DIR"
    [[ "$PURGE_DOWNLOADS" == "1" && -d "$DOWNLOAD_DIR" ]] && rm -rf "$DOWNLOAD_DIR"
  fi
  echo "[DONE]"; exit 0
fi

# host apt fixes
echo "[*] Checking apt sources on host..."
if [ -f /etc/apt/sources.list.d/google-chrome.list ]; then
  if ! apt-get update -o Dir::Etc::sourcelist="sources.list.d/google-chrome.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" >/dev/null 2>&1; then
    echo "[!] Disabling invalid chrome apt source on host..."; mv /etc/apt/sources.list.d/google-chrome.list /etc/apt/sources.list.d/google-chrome.list.disabled || true
  fi
fi
apt-get update -y -qq || true; apt-get install -y -qq curl dnsutils ca-certificates >/dev/null 2>&1 || true

# choices
fetch_choices() { echo "[*] Fetching choices: $CHOICES_URL"; CHOICES_RAW="$(curl -fsSL "$CHOICES_URL" || true)"; [[ -n "${CHOICES_RAW:-}" ]] || return 1; echo "$CHOICES_RAW" | awk -F'|' 'BEGIN{OFS="|"} /^[[:space:]]*#/ {next} NF>=3 {gsub(/^[[:space:]]+|[[:space:]]+$/,"",$1); gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); gsub(/^[[:space:]]+|[[:space:]]+$/,"",$3); print $1,$2,$3 }'; }

if [[ -z "$MT5_URL" ]]; then
  CHOICES="$(fetch_choices || true)"
  if [[ -n "${CHOICES:-}" ]]; then
    echo "[=] Available installers:"; i=0; mapfile -t ROWS < <(echo "$CHOICES"); declare -A ID2LINE
    for line in "${ROWS[@]}"; do i=$((i+1)); IFS='|' read -r id name url <<<"$line"; printf "  %d) [%s] %s\n" "$i" "$id" "$name"; ID2LINE["$id"]="$line"; done
    if [[ -n "$CHOICE_ID" && -n "${ID2LINE[$CHOICE_ID]:-}" ]]; then IFS='|' read -r _ _ MT5_URL <<<"${ID2LINE[$CHOICE_ID]}"; echo "[=] Auto-selected: $CHOICE_ID"; [[ -z "$BROKER" ]] && BROKER="$CHOICE_ID"; fi
    while [[ -z "$MT5_URL" ]]; do
      read -r -p "Select a number or paste a URL: " sel
      if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel>=1 && sel<=i )); then IFS='|' read -r id name MT5_URL <<<"${ROWS[$((sel-1))]}"; [[ -z "$BROKER" ]] && BROKER="$id"
      elif [[ "$sel" =~ ^https?:// ]]; then MT5_URL="$sel"
      else echo "Invalid input. Try again."; fi
    done
  else
    echo "👉 Paste your MT5 installer URL (e.g. Bybit):"; echo "   https://download.metatrader.com/cdn/web/infra.capital.limited/mt5/bybit5setup.exe"; read -r -p "URL: " MT5_URL
  fi
fi

if ! echo "$MT5_URL" | grep -qiE '^https?://'; then echo "❌ Error: URL must start with http:// or https://"; exit 1; fi
if echo "$MT5_URL" | grep -qiE 'github\.com/.*/blob/'; then echo "❌ Error: GitHub 'blob' links are HTML pages. Use Releases or raw.githubusercontent.com URLs."; exit 1; fi

# docker install/start
if ! command -v docker >/dev/null 2>&1; then echo "[+] Installing Docker..."; apt-get update -qq && apt-get install -y -qq docker.io; fi
start_docker_daemon

echo "[=] Using data dir: $DATA_DIR"; echo "[=] Using download cache: $DOWNLOAD_DIR"

sanitize() { LC_ALL=C printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._+\-]+/_/g; s/^_+|_+$//g'; }
FILENAME_FROM_URL="$(basename "${MT5_URL%%\?*}" | sed 's/%20/ /g')"
if [[ -n "$BROKER" ]]; then BROKER_SAFE="$(sanitize "$BROKER")"; INSTALLER_NAME="mt5_${BROKER_SAFE}.exe"
elif [[ -n "$FILENAME_FROM_URL" && "$FILENAME_FROM_URL" =~ \.exe$ ]]; then INSTALLER_NAME="$FILENAME_FROM_URL"
elif [[ -n "$CHOICE_ID" ]]; then INSTALLER_NAME="mt5_${CHOICE_ID}.exe"
else INSTALLER_NAME="mt5_Custom.exe"; fi
CACHED_PATH="${DOWNLOAD_DIR}/${INSTALLER_NAME}"

if [[ -f "$CACHED_PATH" ]]; then echo "[=] Installer found in cache: $CACHED_PATH"
else echo "[+] Downloading MT5 installer (retries + resume)..."; n=1; until curl -fL --retry 5 --retry-all-errors -C - -o "$CACHED_PATH" "$MT5_URL"; do if [[ $n -ge 3 ]]; then echo "❌ Download failed."; exit 1; fi; echo "[!] Retry download ($n/3)"; n=$((n+1)); sleep 2; done; echo "[=] Saved: $CACHED_PATH"; fi

echo "[*] Trying prebuilt Wine image: ${PREFERRED_IMAGE}"; if pull_with_retry "$PREFERRED_IMAGE"; then IMAGE="$PREFERRED_IMAGE"; else echo "[!] Prebuilt not available; using fallback."; IMAGE="$FALLBACK_IMAGE"; fi
echo "[+] Using image: $IMAGE"; pull_with_retry "$IMAGE" || echo "[!] Proceeding with local cache if available."

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then echo "[!] Removing existing container: $CONTAINER_NAME"; docker rm -f "$CONTAINER_NAME" || true; fi

echo "[+] Starting container..."
docker run -d --name "$CONTAINER_NAME" --restart unless-stopped \
  -p "${HTTP_PORT}:80" -p "${VNC_PORT}:5900" \
  -e VNC_PASSWORD="${VNC_PASS}" -e RESOLUTION="1600x900" \
  -v "${DATA_DIR}:/config" -v "${DOWNLOAD_DIR}:/downloads:ro" \
  --shm-size=2g "$IMAGE" >/dev/null
sleep 4

if [[ "$IMAGE" == "$FALLBACK_IMAGE" ]]; then
  echo "[+] Installing Wine inside container (fallback image)..."
  docker exec -it "$CONTAINER_NAME" bash -lc "
set -e
rm -f /etc/apt/sources.list.d/google-chrome*.list || true
apt-get update
dpkg --add-architecture i386
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  wine64 wine32 winbind cabextract wget xvfb xauth x11-xserver-utils winetricks \
  ca-certificates fonts-wqy-zenhei fonts-noto-cjk libglib2.0-bin
"
else
  echo "[=] Wine already preinstalled."
fi

echo "[=] Initializing Wine prefix..."
docker exec -it "$CONTAINER_NAME" bash -lc "
set -e
mkdir -p /config/wineprefix
ln -sfn /config/wineprefix $WINEPREFIX_DIR || true
WINEPREFIX=$WINEPREFIX_DIR winecfg >/dev/null 2>&1 || true
"

if [[ "$DEBUG_INSTALL" == "1" ]]; then
  echo "[=] DEBUG mode: creating desktop shortcut."
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
gio set /root/Desktop/'Install MT5 (Debug).desktop' metadata::trusted true || true
mkdir -p /root/.config/pcmanfm/LXDE
echo -e '[Desktop]\nlaunch_desktop_file=1' > /root/.config/pcmanfm/LXDE/pcmanfm.conf
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
gio set /root/Desktop/MetaTrader5.desktop metadata::trusted true || true
mkdir -p /etc/xdg/lxsession/LXDE
grep -q '/usr/local/bin/mt5' /etc/xdg/lxsession/LXDE/autostart 2>/dev/null || echo '@/usr/local/bin/mt5' >> /etc/xdg/lxsession/LXDE/autostart
mkdir -p /root/.config/pcmanfm/LXDE
echo -e '[Desktop]\nlaunch_desktop_file=1' > /root/.config/pcmanfm/LXDE/pcmanfm.conf
"
fi

detect_ip() {
  for svc in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com" "https://checkip.amazonaws.com"; do ip="$(curl -fsS $svc || true)"; ip="$(echo "$ip" | tr -d '[:space:]')"; [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && { echo "$ip"; return 0; }; done
  ip="$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null || true)"; ip="$(echo "$ip" | head -n1 | tr -d '[:space:]')"; [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && { echo "$ip"; return 0; }; echo ""; }
PUBLIC_IP="$(detect_ip || true)"

echo
echo "=============================================================="
echo " Xquantify · www.xquantify.com"
echo "=============================================================="
echo " Base dir      : $BASE_DIR"
echo " Container     : $CONTAINER_NAME"
echo " Image         : $IMAGE"
echo " Data dir      : $DATA_DIR"
echo " Downloads     : $DOWNLOAD_DIR"
echo " VNC password  : $VNC_PASS"
echo " Installer     : ${INSTALLER_NAME}"
if [[ -n "${PUBLIC_IP}" ]]; then
  echo " noVNC (browser): http://${PUBLIC_IP}:${HTTP_PORT}"
  echo " VNC (client)   : ${PUBLIC_IP}:${VNC_PORT}"
else
  echo " noVNC (browser): http://<YOUR_SERVER_IP>:${HTTP_PORT}"
  echo " VNC (client)   : <YOUR_SERVER_IP>:${VNC_PORT}"
fi
[[ "$DEBUG_INSTALL" == "1" ]] && echo " DEBUG: Double-click 'Install MT5 (Debug)' on the desktop."
echo
echo " Uninstall:"
echo "   sudo ./install_mt5_headless.sh --uninstall --yes"
echo " Full purge (everything created by this script):"
echo "   sudo ./install_mt5_headless.sh --purge-all --yes"
echo "=============================================================="
echo "[DONE] Ready."
