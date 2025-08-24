#!/usr/bin/env bash
# =============================================================================
# Xquantify-MT5-CloudDesk · Headless MT5 on Ubuntu (Docker + noVNC + Wine)
# Author : Xquantify (www.xquantify.com) · Telegram: @xquantify
# GitHub : https://github.com/xquantifyx/Xquantify-MT5-CloudDesk
# License: MIT
# =============================================================================
set -euo pipefail

if [ -f /.dockerenv ] || grep -qa 'docker' /proc/1/cgroup 2>/dev/null; then
  echo "⚠ This installer must be run on the HOST, not inside the mt5 container."
  exit 1
fi

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
Usage: sudo ./install_mt5_headless.sh [options]
  --http-port <port>  --vnc-port <port>  --vnc-pass <pwd>
  --base-dir <dir>    --data-dir <dir>   --download-dir <dir>  --name <container>
  --image <image>
  --mt5-url <url> | --choices-url <raw> [--choice <ID>] [--broker <name>]
  --debug-install
  --uninstall | --purge-all [--purge-images] [--yes]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --http-port) HTTP_PORT="$2"; shift 2;;
    --vnc-port) VNC_PORT="$2"; shift 2;;
    --vnc-pass) VNC_PASS="$2"; shift 2;;
    --base-dir) BASE_DIR="$2"; shift 2;;
    --data-dir) DATA_DIR="$2"; shift 2;;
    --download-dir) DOWNLOAD_DIR="$2"; shift 2;;
    --name) CONTAINER_NAME="$2"; shift 2;;
    --image) IMAGE="$2"; shift 2;;
    --mt5-url) MT5_URL="$2"; shift 2;;
    --choices-url) CHOICES_URL="$2"; shift 2;;
    --choice) CHOICE_ID="$2"; shift 2;;
    --broker) BROKER="$2"; shift 2;;
    --debug-install) DEBUG_INSTALL="1"; shift 1;;
    --uninstall) UNINSTALL="1"; shift 1;;
    --purge-all) PURGE_ALL="1"; shift 1;;
    --purge-images) PURGE_IMAGES="1"; shift 1;;
    --purge-data) PURGE_DATA="1"; shift 1;;
    --purge-downloads) PURGE_DOWNLOADS="1"; shift 1;;
    --yes) ASSUME_YES="1"; shift 1;;
    -h|--help) show_help; exit 0;;
    *) echo "Unknown arg: $1"; show_help; exit 1;;
  esac
done

mkdir -p "$BASE_DIR" "$DATA_DIR" "$DOWNLOAD_DIR" "$LOG_DIR"

echo "=== Xquantify · www.xquantify.com ==="
echo "BASE_DIR      : $BASE_DIR"
echo "HTTP/VNC      : $HTTP_PORT / $VNC_PORT"
echo "IMAGE         : $IMAGE (preferred: $PREFERRED_IMAGE)"
echo "CHOICES_URL   : $CHOICES_URL"
echo "====================================="

confirm() { [[ "$ASSUME_YES" == "1" ]] && return 0; read -r -p "$1 [y/N]: " a; [[ "${a,,}" =~ ^y(es)?$ ]]; }
pull_with_retry(){ local img="$1"; local n=1; while [[ $n -le 3 ]]; do docker pull "$img" >/dev/null 2>&1 && return 0; echo "[!] pull $img fail ($n/3)"; sleep $((n*2)); n=$((n+1)); done; return 1; }

start_docker_daemon(){
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then return 0; fi
  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then systemctl start docker || true
  elif command -v service >/dev/null 2>&1; then service docker start || true; fi
  if ! docker info >/dev/null 2>&1; then nohup dockerd -H unix:///var/run/docker.sock >"$DOCKERD_LOG" 2>&1 & sleep 1; fi
}

# randomize vnc pass if default
if [[ "$VNC_PASS" == "mt5VNCpass" ]]; then VNC_PASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12 || echo Xq$(date +%s))"; echo "[=] VNC password: $VNC_PASS"; fi

# uninstall/cleanup
if [[ "$UNINSTALL" == "1" || "$PURGE_ALL" == "1" ]]; then
  [[ "$PURGE_ALL" == "1" ]] && PURGE_DATA="1" PURGE_DOWNLOADS="1" PURGE_IMAGES="1" ASSUME_YES="1"
  echo "[*] Uninstalling..."
  if command -v docker >/dev/null 2>&1; then
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || echo "   - container not found"
    if [[ "$PURGE_IMAGES" == "1" ]]; then
      echo "   - remove images:"
      docker rmi "$PREFERRED_IMAGE" >/dev/null 2>&1 || echo "     (not present)"
      docker rmi "$FALLBACK_IMAGE"  >/dev/null 2>&1 || echo "     (not present)"
    fi
  fi
  if [[ "$PURGE_ALL" == "1" ]]; then
    echo "   - delete BASE_DIR: $BASE_DIR"; ls -lah "$BASE_DIR" 2>/dev/null || true; rm -rf "$BASE_DIR" || true
    rm -f "$DOCKERD_LOG" || true
  else
    [[ "$PURGE_DATA" == "1" && -d "$DATA_DIR" ]] && { echo "   - delete DATA_DIR: $DATA_DIR"; ls -lah "$DATA_DIR"; rm -rf "$DATA_DIR"; }
    [[ "$PURGE_DOWNLOADS" == "1" && -d "$DOWNLOAD_DIR" ]] && { echo "   - delete DOWNLOAD_DIR: $DOWNLOAD_DIR"; ls -lah "$DOWNLOAD_DIR"; rm -rf "$DOWNLOAD_DIR"; }
  fi
  echo "[DONE]"; exit 0
fi

# host apt fixes
if [ -f /etc/apt/sources.list.d/google-chrome.list ]; then mv /etc/apt/sources.list.d/google-chrome.list /etc/apt/sources.list.d/google-chrome.list.disabled || true; fi
apt-get update -y -qq || true; apt-get install -y -qq curl ca-certificates dnsutils >/dev/null 2>&1 || true

# fetch choices
fetch_choices(){ curl -fsSL "$CHOICES_URL" | awk -F'|' 'BEGIN{OFS="|"} /^[[:space:]]*#/ {next} NF>=3 {gsub(/^[[:space:]]+|[[:space:]]+$/,"",$1); gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); gsub(/^[[:space:]]+|[[:space:]]+$/,"",$3); print $1,$2,$3 }'; }
if [[ -z "${MT5_URL}" ]]; then
  CHOICES="$(fetch_choices || true)"
  if [[ -n "$CHOICES" ]]; then
    echo "[=] Available installers:"; i=0; mapfile -t ROWS < <(echo "$CHOICES")
    declare -A ID2LINE; for line in "${ROWS[@]}"; do i=$((i+1)); IFS='|' read -r id name url <<<"$line"; printf "  %d) [%s] %s\n" "$i" "$id" "$name"; ID2LINE["$id"]="$line"; done
    if [[ -n "$CHOICE_ID" && -n "${ID2LINE[$CHOICE_ID]:-}" ]]; then IFS='|' read -r _ _ MT5_URL <<<"${ID2LINE[$CHOICE_ID]}"; [[ -z "$BROKER" ]] && BROKER="$CHOICE_ID"; fi
    while [[ -z "$MT5_URL" ]]; do
      read -r -p "Select a number or paste a URL: " sel
      if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel>=1 && sel<=i )); then IFS='|' read -r id name MT5_URL <<<"${ROWS[$((sel-1))]}"; [[ -z "$BROKER" ]] && BROKER="$id"
      elif [[ "$sel" =~ ^https?:// ]]; then MT5_URL="$sel"
      else echo "Invalid input"; fi
    done
  else
    echo "👉 Paste your MT5 installer URL (e.g. Bybit):"; read -r -p "URL: " MT5_URL
  fi
fi
[[ "$MT5_URL" =~ ^https?:// ]] || { echo "❌ invalid URL"; exit 1; }
if echo "$MT5_URL" | grep -qi 'github.com/.*/blob/'; then echo "❌ use Releases/raw URL, not blob page"; exit 1; fi

# docker
if ! command -v docker >/dev/null 2>&1; then apt-get update -qq && apt-get install -y -qq docker.io; fi
start_docker_daemon

echo "[=] Using data: $DATA_DIR"
echo "[=] Using cache: $DOWNLOAD_DIR"

sanitize(){ LC_ALL=C printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._+\-]+/_/g; s/^_+|_+$//g'; }
FN="$(basename "${MT5_URL%%\?*}")"
if [[ -n "$BROKER" ]]; then INSTALLER_NAME="mt5_$(sanitize "$BROKER").exe"
elif [[ "$FN" =~ \.exe$ ]]; then INSTALLER_NAME="$FN"
elif [[ -n "$CHOICE_ID" ]]; then INSTALLER_NAME="mt5_${CHOICE_ID}.exe"
else INSTALLER_NAME="mt5_Custom.exe"; fi
CACHED="${DOWNLOAD_DIR}/${INSTALLER_NAME}"

if [[ -f "$CACHED" ]]; then echo "[=] Use cached: $CACHED"; else
  echo "[+] Downloading..."; curl -fL --retry 5 --retry-all-errors -C - -o "$CACHED" "$MT5_URL"; echo "[=] Saved: $CACHED"; fi

echo "[*] Try prebuilt image: $PREFERRED_IMAGE"; if pull_with_retry "$PREFERRED_IMAGE"; then IMAGE="$PREFERRED_IMAGE"; else echo "[!] fallback to $FALLBACK_IMAGE"; IMAGE="$FALLBACK_IMAGE"; fi
pull_with_retry "$IMAGE" || true

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER_NAME" --restart unless-stopped \
  -p "${HTTP_PORT}:80" -p "${VNC_PORT}:5900" \
  -e VNC_PASSWORD="${VNC_PASS}" -e RESOLUTION="1600x900" \
  -v "${DATA_DIR}:/config" -v "${DOWNLOAD_DIR}:/downloads:ro" \
  --shm-size=2g "$IMAGE" >/dev/null
sleep 3

if [[ "$IMAGE" == "$FALLBACK_IMAGE" ]]; then
  docker exec -it "$CONTAINER_NAME" bash -lc "
set -e
rm -f /etc/apt/sources.list.d/google-chrome*.list || true
apt-get update
dpkg --add-architecture i386
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  wine64 wine32 winbind cabextract wget xvfb xauth x11-xserver-utils winetricks \
  ca-certificates fonts-wqy-zenhei fonts-noto-cjk
"
fi

docker exec -it "$CONTAINER_NAME" bash -lc "
set -e
mkdir -p /config/wineprefix
ln -sfn /config/wineprefix $WINEPREFIX_DIR || true
WINEPREFIX=$WINEPREFIX_DIR winecfg >/dev/null 2>&1 || true
"

# function inside container: write desktop + force no prompt (cover all profiles)
fix_desktop_cfg='
set -e
# 1) desktop file
mkdir -p /root/Desktop
cat >/root/Desktop/MetaTrader5.desktop <<\"EOF\"
[Desktop Entry]
Type=Application
Name=MetaTrader 5
Comment=Launch MetaTrader 5 (Wine)
Exec=/usr/local/bin/mt5
Icon=utilities-terminal
Terminal=false
Categories=Finance;
EOF
chmod +x /root/Desktop/MetaTrader5.desktop

# 2) pcmanfm + libfm configs in multiple locations
for d in \"/root/.config/pcmanfm/default\" \"/root/.config/pcmanfm/LXDE\" \"/etc/xdg/pcmanfm/default\" \"/etc/xdg/pcmanfm/LXDE\"; do
  mkdir -p \"$d\"
  printf \"[Desktop]\\nlaunch_desktop_file=1\\n\" > \"$d/pcmanfm.conf\"
done
for d in \"/etc/xdg/libfm\" \"/root/.config/libfm\"; do
  mkdir -p \"$d\"
  printf \"[config]\\nquick_exec=1\\nconfirm_run=0\\n\" > \"$d/libfm.conf\"
done

# 3) restart file manager
killall pcmanfm >/dev/null 2>&1 || true
pcmanfm --daemon &>/dev/null &
'

if [[ "$DEBUG_INSTALL" == "1" ]]; then
  docker exec -it "$CONTAINER_NAME" bash -lc "
set -e
cp '/downloads/${INSTALLER_NAME}' '$MT5_SETUP_PATH'
cat >/usr/local/bin/mt5-install-debug <<'EOD'
#!/usr/bin/env bash
export WINEPREFIX='/root/.wine'
exec wine '/root/mt5setup.exe'
EOD
chmod +x /usr/local/bin/mt5-install-debug
mkdir -p /root/Desktop
cat >/root/Desktop/'Install MT5 (Debug).desktop' <<'EOD'
[Desktop Entry]
Type=Application
Name=Install MT5 (Debug)
Exec=/usr/local/bin/mt5-install-debug
Icon=system-software-install
Terminal=false
Categories=Utility;
EOD
chmod +x /root/Desktop/'Install MT5 (Debug).desktop'
${fix_desktop_cfg}
"
else
  docker exec -it "$CONTAINER_NAME" bash -lc "
set -e
cp '/downloads/${INSTALLER_NAME}' '$MT5_SETUP_PATH'
WINEPREFIX=$WINEPREFIX_DIR wine '$MT5_SETUP_PATH' /silent || true
cat >/usr/local/bin/mt5 <<'EOD'
#!/usr/bin/env bash
export WINEPREFIX='/root/.wine'
exec wine 'C:\\\\Program Files\\\\MetaTrader 5\\\\terminal64.exe'
EOD
chmod +x /usr/local/bin/mt5
${fix_desktop_cfg}
"
fi

detect_ip(){ for s in https://api.ipify.org https://ifconfig.me https://icanhazip.com https://checkip.amazonaws.com; do ip=$(curl -fsS $s || true); ip=${ip//[$'\n\r\t ']}; [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && { echo $ip; return; }; done; echo ""; }
PUBIP="$(detect_ip)"

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
if [[ -n "$PUBIP" ]]; then
  echo " noVNC (browser): http://${PUBIP}:${HTTP_PORT}"
  echo " VNC (client)   : ${PUBIP}:${VNC_PORT}"
else
  echo " noVNC (browser): http://<YOUR_SERVER_IP>:${HTTP_PORT}"
  echo " VNC (client)   : <YOUR_SERVER_IP>:${VNC_PORT}"
fi
echo " Uninstall:"
echo "   sudo ./install_mt5_headless.sh --uninstall --yes"
echo " Full purge:"
echo "   sudo ./install_mt5_headless.sh --purge-all --yes"
echo "=============================================================="
echo "[DONE] Ready."
