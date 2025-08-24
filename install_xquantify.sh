#!/usr/bin/env bash
# xquantify_installer.sh
# Installer & uninstaller for Xquantify-MT5-CloudDesk (ZIP-based, no git clone).
# Features:
# - Install Docker + Compose v2
# - Firewall setup with SSH rate limiting
# - Fetch project ZIP & deploy
# - systemd auto-start
# - Uninstall mode cleans EVERYTHING

set -euo pipefail

### ===== CONFIG =====
REPO_ZIP_URL="${REPO_ZIP_URL:-https://github.com/xquantifyx/Xquantify-MT5-CloudDesk/archive/refs/heads/main.zip}"
APP_DIR="${APP_DIR:-/opt/Xquantify-MT5-CloudDesk}"
APP_PORT="${APP_PORT:-8000}"
DOMAIN="${DOMAIN:-your.domain.com}"
ADMIN_EMAIL="${ADMIN_EMAIL:-you@example.com}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_NAME="${DB_NAME:-xquantify}"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-5432}"
EXPOSE_APP_PORT="${EXPOSE_APP_PORT:-true}"   # true|false
SYSTEMD_UNIT="/etc/systemd/system/xquantify.service"
### ==================

say()  { echo -e "\033[1;32m$*\033[0m"; }
warn() { echo -e "\033[1;33m$*\033[0m"; }
err()  { echo -e "\033[1;31m$*\033[0m" >&2; }

install_prereqs() {
  say "📦 Installing prerequisites..."
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release unzip ufw docker.io docker-compose-plugin
  systemctl enable --now docker
}

setup_firewall() {
  say "🔐 Configuring UFW..."
  ufw default deny incoming || true
  ufw default allow outgoing || true
  ufw allow OpenSSH || true
  ufw limit OpenSSH || true
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
  if [[ "$EXPOSE_APP_PORT" == "true" ]]; then
    ufw allow "$APP_PORT"/tcp || true
  fi
  echo "y" | ufw enable >/dev/null || true
  ufw status verbose || true
}

fetch_repo_zip() {
  say "⬇️ Downloading project ZIP..."
  mkdir -p "$APP_DIR"
  cd /tmp
  curl -fL "$REPO_ZIP_URL" -o project.zip
  rm -rf Xquantify-MT5-CloudDesk-main
  unzip -q project.zip
  rm -rf "${APP_DIR:?}"/*
  mv Xquantify-MT5-CloudDesk-main/* "$APP_DIR"/
  rm -rf project.zip Xquantify-MT5-CloudDesk-main
}

ensure_env_file() {
  cd "$APP_DIR"
  if [[ -z "$DB_PASSWORD" ]]; then
    if command -v openssl >/dev/null 2>&1; then
      DB_PASSWORD="ChangeMe_$(openssl rand -hex 8)"
    else
      DB_PASSWORD="ChangeMe_$(date +%s%N)"
    fi
  fi
  if [[ ! -f ".env" ]]; then
    cat > .env <<ENV
APP_ENV=production
APP_PORT=$APP_PORT

DOMAIN=$DOMAIN
ADMIN_EMAIL=$ADMIN_EMAIL

DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_NAME=$DB_NAME
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
ENV
  fi
  say "✔ .env ready"
}

compose_up() {
  cd "$APP_DIR"
  sed -i '/^version:/d' docker-compose.yaml || true
  say "🚀 Starting stack..."
  docker compose up --build -d
  docker compose ps
}

create_systemd() {
  say "🧩 Creating systemd unit..."
  cat > "$SYSTEMD_UNIT" <<EOF
[Unit]
Description=Xquantify-MT5-CloudDesk (docker compose)
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
RemainAfterExit=yes
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable xquantify
}

post_info() {
  say "✅ Install complete!"
  echo "Visit: https://$DOMAIN/ (or http://<IP>:$APP_PORT/health if EXPOSE_APP_PORT=true)"
}

uninstall() {
  warn "⚠ Uninstalling Xquantify-MT5-CloudDesk..."
  if systemctl is-enabled --quiet xquantify 2>/dev/null; then
    systemctl stop xquantify || true
    systemctl disable xquantify || true
  fi
  rm -f "$SYSTEMD_UNIT"
  systemctl daemon-reload

  if [[ -d "$APP_DIR" ]]; then
    cd "$APP_DIR" || true
    docker compose down -v || true
  fi
  docker system prune -af || true
  rm -rf "$APP_DIR"

  say "🧹 Cleanup complete:"
  echo "- Removed app directory: $APP_DIR"
  echo "- Removed systemd unit: $SYSTEMD_UNIT"
  echo "- Stopped & removed containers, images, and volumes"
}

main() {
  if [[ "${1:-}" == "uninstall" ]]; then
    uninstall
    exit 0
  fi

  install_prereqs
  setup_firewall
  fetch_repo_zip
  ensure_env_file
  compose_up
  create_systemd
  post_info
}

main "$@"
