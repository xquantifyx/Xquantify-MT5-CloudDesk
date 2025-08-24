
# 🚀 Xquantify‑MT5‑CloudDesk

A production‑ready, Dockerized scaffold for running a FastAPI service behind an automatic HTTPS reverse proxy (Caddy).  
Includes Postgres, `.env` config, GitHub Actions CI, and a step‑by‑step Ubuntu VPS guide.

---

## Contents

- `main.py` — Minimal FastAPI app (`/` and `/health`).
- `Dockerfile` — Slim Python 3.11 image, non‑root user, cache‑friendly.
- `docker-compose.yaml` — `app` + `db` + `caddy` (HTTPS) services.
- `Caddyfile` — Reverse proxy & TLS via Let's Encrypt.
- `.env.example` — Clear environment variables.
- `.dockerignore` / `.gitignore` — Clean builds and repos.
- `requirements.txt` — FastAPI, Uvicorn, etc.
- `.github/workflows/ci.yml` — CI to build & lint on PRs.
- `LICENSE.md` — MIT License.

---

## Quick Start (Local)

```bash
# 1) Clone & enter
git clone https://github.com/xquantifyx/Xquantify-MT5-CloudDesk.git
cd Xquantify-MT5-CloudDesk

# 2) Prepare env
cp .env.example .env
# (Optional) edit .env to change APP_PORT or DB_*
nano .env

# 3) Run (HTTP on localhost:8000; HTTPS via caddy requires a public domain)
docker compose up --build
```

Visit:
- App: http://localhost:8000/
- Health: http://localhost:8000/health

> If you don't have a domain locally, Caddy will still start but won't obtain certs. For local HTTPS you can map a test domain in `/etc/hosts` pointing to 127.0.0.1, but ACME will fail (not publicly reachable).

---

## Deploy on Ubuntu VPS (20.04/22.04/24.04)

### 1) Install dependencies
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git docker.io docker-compose ufw
sudo usermod -aG docker $USER    # log out/in or run: newgrp docker
```

### 2) Clone & configure
```bash
git clone https://github.com/xquantifyx/Xquantify-MT5-Cloud-Desk.git
cd Xquantify-MT5-Cloud-Desk
cp .env.example .env
nano .env    # set DOMAIN, ADMIN_EMAIL, DB_* as needed
```

**Important `.env` keys:**
```env
# App
APP_ENV=production
APP_PORT=8000

# Domain & TLS
DOMAIN=your.domain.com
ADMIN_EMAIL=you@example.com

# Database
DB_USER=postgres
DB_PASSWORD=secret
DB_NAME=xquantify
DB_HOST=db
DB_PORT=5432
```

### 3) DNS
Create an **A record** for `your.domain.com` pointing to your VPS public IP.

### 4) Open firewall
```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
# Optional if you want direct app access (not needed in prod)
sudo ufw allow 8000/tcp
sudo ufw enable
sudo ufw status
```

### 5) Start services
```bash
docker compose up --build -d
docker compose logs -f caddy   # watch for "certificate obtained"
```

Visit:
- **HTTPS**: https://your.domain.com/
- Health: https://your.domain.com/health

Caddy manages TLS automatically and renews certificates for you.

### 6) Auto‑start on reboot (systemd)
```bash
sudo tee /etc/systemd/system/xquantify.service >/dev/null <<'EOF'
[Unit]
Description=Xquantify-MT5-CloudDesk (docker-compose)
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
WorkingDirectory=/home/<YOUR_USER>/Xquantify-MT5-Cloud-Desk
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable xquantify
sudo systemctl start xquantify
sudo systemctl status xquantify --no-pager
```
> Replace `<YOUR_USER>` and adjust the path if different.

---

## Development

- Live logs:
  ```bash
  docker compose logs -f app
  docker compose logs -f db
  docker compose logs -f caddy
  ```
- Rebuild after code changes:
  ```bash
  docker compose up --build -d
  ```
- Exec into container:
  ```bash
  docker compose exec app bash
  ```

---

## Security / Production Tips

- In production, **remove** the `app` port mapping from `docker-compose.yaml` so traffic only passes through Caddy.
- Use strong DB credentials in `.env`.
- Keep your system & Docker images up to date:
  ```bash
  docker compose pull && docker compose up -d
  ```
- Backups: mount a volume for Postgres (`postgres_data`) and snapshot it regularly.

---

## Troubleshooting

- **Cannot reach site over HTTPS**: 
  - DNS A record not pointing to the VPS yet (propagation can take a few minutes).
  - Port 80/443 blocked: check `ufw status` and your cloud provider’s firewall.
- **`permission denied` with Docker**:
  - Log out/in after `usermod -aG docker $USER` (or `newgrp docker`).
- **Port already in use**:
  - Change `APP_PORT` in `.env` and restart.
- **Caddy cert errors**:
  - Ensure your domain resolves publicly to your VPS IP and port 80 is reachable for HTTP‑01 challenge.
- **Recreate everything cleanly**:
  ```bash
  docker compose down -v
  docker compose up --build -d
  ```

---

## File Tree

```
.
├── Caddyfile
├── Dockerfile
├── docker-compose.yaml
├── main.py
├── requirements.txt
├── .env.example
├── .dockerignore
├── .gitignore
├── README.md
├── LICENSE.md
└── .github/
    └── workflows/
        └── ci.yml
```

---

## License

MIT — see `LICENSE.md`.
