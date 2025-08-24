# 🚀 Xquantify-MT5-CloudDesk

A production-ready, Dockerized scaffold for running a FastAPI service behind an automatic HTTPS reverse proxy (Caddy).  
Includes PostgreSQL, `.env` config, GitHub Actions CI, and a full **installer/uninstaller script** for Ubuntu VPS.

---

## 📦 Features

- FastAPI app with `/` and `/health`
- Dockerfile (Python 3.11 slim, cache-friendly, non-root user)
- `docker-compose.yaml` with:
  - `app` (FastAPI/Uvicorn)
  - `db` (PostgreSQL 15)
  - `caddy` (auto HTTPS via Let’s Encrypt)
- `.env.example` for environment variables
- `.dockerignore` / `.gitignore`
- GitHub Actions CI workflow
- MIT License
- **Lifecycle script** (`xquantify_lifecycle.sh`) with:
  - `install` (default)
  - `uninstall` (remove app only)
  - `purge` (dangerous: wipe Docker + firewall reset)

---

## 🚀 Quick Start (Local)

```bash
# Clone or unzip repo, then:
cp .env.example .env
nano .env   # edit values (DB password, DOMAIN, etc.)

docker compose up --build -d
```

Visit:
- App: http://localhost:8000/
- Health: http://localhost:8000/health

---

## ☁️ Deploy on Ubuntu VPS

### 1. Upload or download repo
```bash
curl -L https://github.com/xquantifyx/Xquantify-MT5-CloudDesk/archive/refs/heads/main.zip -o project.zip
unzip project.zip
cd Xquantify-MT5-CloudDesk-main
```

### 2. Run lifecycle installer
```bash
chmod +x xquantify_lifecycle.sh
sudo ./xquantify_lifecycle.sh install
```

- Installs Docker + Compose v2
- Configures UFW firewall (SSH safe, HTTP/HTTPS open)
- Downloads repo from ZIP
- Creates `.env` if missing
- Starts containers
- Creates systemd unit `xquantify.service` for auto-start on reboot

---

## ⚙️ Manage Lifecycle

### Install (default)
```bash
sudo ./xquantify_lifecycle.sh install
```

### Uninstall (remove only app)
```bash
sudo ./xquantify_lifecycle.sh uninstall
```
- Stops containers
- Removes app images/volumes
- Deletes `/opt/Xquantify-MT5-CloudDesk`
- Removes systemd unit

### Purge (⚠️ dangerous: full wipe)
```bash
sudo ./xquantify_lifecycle.sh purge
```
- Stops & removes **all Docker containers/images/volumes/networks (system-wide)**
- Uninstalls Docker packages
- Removes `/var/lib/docker` and `/var/lib/containerd`
- Removes Docker apt repo & GPG key
- Resets & disables UFW firewall
- Deletes `/opt/Xquantify-MT5-CloudDesk` and systemd unit

> You must type `PURGE` to confirm.

---

## 🔧 Service Management

- Start app:
  ```bash
  sudo systemctl start xquantify
  ```
- Stop app:
  ```bash
  sudo systemctl stop xquantify
  ```
- Check status:
  ```bash
  sudo systemctl status xquantify --no-pager
  ```
- Logs:
  ```bash
  docker compose -f /opt/Xquantify-MT5-CloudDesk/docker-compose.yaml logs -f app
  docker compose -f /opt/Xquantify-MT5-CloudDesk/docker-compose.yaml logs -f caddy
  ```

---

## 🔑 Environment Variables (`.env`)

```env
APP_ENV=production
APP_PORT=8000

DOMAIN=your.domain.com
ADMIN_EMAIL=you@example.com

DB_USER=postgres
DB_PASSWORD=ChangeMeStrong
DB_NAME=xquantify
DB_HOST=db
DB_PORT=5432
```

---

## 🧹 Uninstall Details

`uninstall` mode removes:
- Containers, images, and volumes **used by this stack**
- App folder: `/opt/Xquantify-MT5-CloudDesk`
- Systemd service: `/etc/systemd/system/xquantify.service`

`purge` mode removes:
- **All Docker** containers/images/volumes/networks
- Docker packages, repo, keys
- `/var/lib/docker`, `/var/lib/containerd`
- Resets + disables UFW firewall
- App folder + systemd service

---

## 📝 License

MIT — see [LICENSE.md](LICENSE.md)

---
