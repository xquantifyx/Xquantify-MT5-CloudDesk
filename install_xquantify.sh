#!/usr/bin/env bash
# xquantify_lifecycle.sh
# Install / Uninstall / PURGE for Xquantify-MT5-CloudDesk (no git clone).
# Modes:
#   install  (default)
#   uninstall
#   purge    (dangerous: nukes Docker + UFW + all docker data)
#
# You may override config via environment variables (see CONFIG section).

set -euo pipefail

# -------------------- CONFIG (override via env) --------------------
REPO_ZIP_URL="${REPO_ZIP_URL:-https://github.com/xquantifyx/Xquantify-MT5-CloudDesk/archive/refs/heads/main.zip}"
APP_DIR="${APP_DIR:-/opt/Xquantify-MT5-CloudDesk}"
APP_PORT="${APP_PORT:-8000}"

DOMAIN="${DOMAIN:-your.domain.com}"
ADMIN_EMAIL="${ADMIN_EMAIL:-you@example.com}"

DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-}"     # If empty, a random one will be generated
DB_NAME="${DB_NAME:-xquantify}"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-5432}"

EXPOSE_APP_PORT="${EXPOSE_APP_PORT:-true}"   # true|false
SYSTEMD_UNIT="/etc/systemd/system/xquantify.service"
# -------------------------------------------------------------------

say()  { echo -e "\033[1;32m$*\033[0m"; }
warn() { echo -e "\033[1;33m$*\033[0m"; }
err()  { echo -e "\033[1;31m$*\033[0m" >&2; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<USAGE
Usage: sudo bash $0 [install|uninstall|purge]

Modes:
  install   - Install Docker+Compose, set firewall, deploy app from ZIP, enable systemd (default)
  uninstall - Stop & remove app containers/images/volumes, delete app dir & systemd unit
  purge     - DANGEROUS: uninstall Docker, wipe ALL docker data system-wide, reset & disable UFW, remove Docker apt repo

Environment overrides (examples):
  DOMAIN=api.example.com ADMIN_EMAIL=ops@example.com APP_DIR=/opt/Xquantify \\
  DB_PASSWORD='S3cure!' EXPOSE_APP_PORT=false bash $0 install
USAGE
}

ensure_rootish() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    warn "Run this script with sudo/root to avoid permission issues."
  fi
}

install_prereqs() {
  say "📦 Installing prerequisites..."
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release unzip ufw

  if ! need_cmd docker; then
    say "🐳 Installing Docker Engine + Compose v2 plugin..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    UBUNTU_CODENAME="$(. /etc/os-release && echo "$UBUNTU_CODENAME")"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" > /etc/apt/sources.list.d/docker.list

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
  else
    say "✔ Docker: $(docker --version)"
    if ! docker compose version >/dev/null 2>&1; then
      apt-get install -y docker-compose-plugin
    fi
    say "✔ Compose: $(docker compose version | head -n1)"
  fi
}

setup_firewall() {
  say "🔐 Configuring UFW (safe defaults + SSH rate limiting)..."
  ufw default deny incoming || true
  ufw default allow outgoing || true
  ufw allow OpenSSH || true
  ufw limit OpenSSH || true
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
  if [[ "${EXPOSE_APP_PORT}" == "true" ]]; then
    ufw allow "${APP_PORT}"/tcp || true
  fi
  echo "y" | ufw enable >/dev/null || true
  ufw status verbose || true
}

fetch_repo_from_zip() {
  say "⬇️ Downloading project ZIP..."
  mkdir -p "${APP_DIR}"
  cd /tmp
  curl -fL "${REPO_ZIP_URL}" -o project.zip
  rm -rf Xquantify-MT5-CloudDesk-main
  unzip -q project.zip
  rm -rf "${APP_DIR:?}"/*
  mv Xquantify-MT5-CloudDesk-main/* "${APP_DIR}/"
  rm -rf project.zip Xquantify-MT5-CloudDesk-main
  say "📁 Project placed at: ${APP_DIR}"
}

ensure_env_file() {
  cd "${APP_DIR}"
  if [[ -z "${DB_PASSWORD}" ]]; then
    if command -v openssl >/dev/null 2>&1; then
      DB_PASSWORD="ChangeMe_$(openssl rand -hex 8)"
    else
      DB_PASSWORD="ChangeMe_$(date +%s%N)"
    fi
  fi
  if [[ ! -f ".env" ]]; then
    say "⚙️ Creating .env ..."
    cat > .env <<ENV
APP_ENV=production
APP_PORT=${APP_PORT}

DOMAIN=${DOMAIN}
ADMIN_EMAIL=${ADMIN_EMAIL}

DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=${DB_NAME}
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
ENV
  else
    warn ".env exists — leaving as is."
  fi
  say "✔ .env ready"
}

compose_up() {
  cd "${APP_DIR}"
  sed -i '/^version:/d' docker-compose.yaml || true
  say "🚀 Starting stack..."
  docker compose up --build -d
  docker compose ps
}

create_systemd() {
  say "🧩 Creating systemd unit…"
  cat > "${SYSTEMD_UNIT}" <<EOF
[Unit]
Description=Xquantify-MT5-CloudDesk (docker compose)
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
RemainAfterExit=yes
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable xquantify
  say "✔ Enabled autostart: systemctl enable xquantify"
}

post_install_info() {
  local IP
  IP="$(curl -4 -s ifconfig.me || echo '<server-ip>')"
  say "✅ Install complete!"
  echo "Manage:"
  echo "  systemctl start|stop|status xquantify"
  echo "  docker compose -f ${APP_DIR}/docker-compose.yaml logs -f app"
  echo "  docker compose -f ${APP_DIR}/docker-compose.yaml logs -f caddy"
  echo
  echo "If DNS is set for ${DOMAIN}:"
  echo "  https://${DOMAIN}/  |  https://${DOMAIN}/health"
  if [[ "${EXPOSE_APP_PORT}" == "true" ]]; then
    echo "Debug without DNS:"
    echo "  http://${IP}:${APP_PORT}/  |  http://${IP}:${APP_PORT}/health"
  fi
}

uninstall_app() {
  warn "⚠ Uninstalling app (containers/images/volumes for this stack, systemd unit, app dir)…"
  if systemctl is-enabled --quiet xquantify 2>/dev/null; then
    systemctl stop xquantify || true
    systemctl disable xquantify || true
  fi
  rm -f "${SYSTEMD_UNIT}" || true
  systemctl daemon-reload || true

  if [[ -d "${APP_DIR}" ]]; then
    ( cd "${APP_DIR}" && docker compose down -v || true )
  fi
  # Remove only images used by this compose project (best effort)
  docker image prune -af || true

  rm -rf "${APP_DIR}"
  say "🧹 Uninstall complete:"
  echo "- Removed ${APP_DIR}"
  echo "- Removed systemd unit ${SYSTEMD_UNIT}"
  echo "- Stopped & removed containers/volumes for this app"
}

purge_everything() {
  cat <<'EOWARN'
⚠️  PURGE MODE WARNING
This will:
  - Stop & remove ALL Docker containers, images, volumes, networks (system-wide)
  - Uninstall Docker packages
  - Remove Docker apt repo & GPG key
  - Reset and DISABLE UFW (firewall rules cleared)
  - Remove the app directory and systemd unit
Type EXACTLY: PURGE to continue (or anything else to abort).
EOWARN
  read -r -p "CONFIRM (type PURGE): " ANSW
  if [[ "${ANSW:-}" != "PURGE" ]]; then
    err "Aborted."
    exit 1
  fi

  # First do app uninstall to be thorough
  uninstall_app || true

  warn "Stopping ALL Docker containers…"
  docker ps -q | xargs -r docker stop || true

  warn "Removing ALL Docker containers…"
  docker ps -aq | xargs -r docker rm -f || true

  warn "Removing ALL Docker images…"
  docker images -aq | xargs -r docker rmi -f || true

  warn "Removing ALL Docker volumes…"
  docker volume ls -q | xargs -r docker volume rm -f || true

  warn "Removing ALL Docker networks (except default)…"
  docker network ls --format '{{.Name}}' | grep -vE '^(bridge|host|none)$' | xargs -r docker network rm || true

  warn "Pruning any leftovers…"
  docker system prune -af || true

  warn "Uninstalling Docker packages…"
  apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker.io || true
  apt-get autoremove -y --purge || true

  warn "Removing Docker data directories…"
  rm -rf /var/lib/docker /var/lib/containerd || true

  warn "Removing Docker apt repo & key…"
  rm -f /etc/apt/sources.list.d/docker.list || true
  rm -f /etc/apt/keyrings/docker.gpg || true
  apt-get update -y || true

  warn "Resetting and DISABLING UFW (firewall)…"
  yes | ufw reset || true
  ufw disable || true
  ufw status verbose || true

  say "💣 PURGE complete. Docker removed, firewall reset & disabled, app deleted."
  echo "If you need a fresh install later, run:"
  echo "  bash $0 install"
}

install_flow() {
  install_prereqs
  setup_firewall
  fetch_repo_from_zip
  ensure_env_file
  compose_up
  create_systemd
  post_install_info
}

# --------------- entrypoint ---------------
MODE="${1:-install}"
ensure_rootish

case "$MODE" in
  install)
    install_flow
    ;;
  uninstall)
    uninstall_app
    ;;
  purge)
    purge_everything
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    err "Unknown mode: $MODE"
    usage
    exit 2
    ;;
esac
