#!/usr/bin/env bash
# install_xquantify_zip.sh
# One-shot installer for Xquantify-MT5-CloudDesk using ZIP (no git required)

set -euo pipefail

### ====== CONFIG ======
REPO_URL="https://github.com/xquantifyx/Xquantify-MT5-CloudDesk/archive/refs/heads/main.zip"
APP_DIR="/opt/Xquantify-MT5-CloudDesk"
APP_PORT="8000"

# HTTPS config
DOMAIN="your.domain.com"
ADMIN_EMAIL="you@example.com"

# DB config
DB_USER="postgres"
DB_PASSWORD="ChangeMe_$(openssl rand -hex 8)"
DB_NAME="xquantify"
DB_HOST="db"
DB_PORT="5432"

# Expose raw app port (debugging)
EXPOSE_APP_PORT=true
### ====================

say() { echo -e "\033[1;32m$*\033[0m"; }

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
    ufw allow "${APP_PORT}"/tcp || true
  fi
  echo "y" | ufw enable >/dev/null || true
  ufw status verbose || true
}

fetch_repo_zip() {
  say "⬇️ Downloading project ZIP..."
  mkdir -p "$APP_DIR"
  cd /tmp
  curl -L "$REPO_URL" -o project.zip
  rm -rf Xquantify-MT5-CloudDesk-main
  unzip -q project.zip
  rm -rf "$APP_DIR"/*
  mv Xquantify-MT5-CloudDesk-main/* "$APP_DIR"/
  rm -rf project.zip Xquantify-MT5-CloudDesk-main
}

ensure_env_file() {
  say "⚙️ Creating .env..."
  cat > "$APP_DIR/.env" <<ENV
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
}

start_stack() {
  cd "$APP_DIR"
  sed -i '/^version:/d' docker-compose.yaml || true
  say "🚀 Starting stack..."
  docker compose up --build -d
  docker compose ps
}

main() {
  install_prereqs
  setup_firewall
  fetch_repo_zip
  ensure_env_file
  start_stack
  say "✅ Deployment complete!"
  echo "Check: http://${DOMAIN} or http://<server-ip>:${APP_PORT}/health"
}

main "$@"
