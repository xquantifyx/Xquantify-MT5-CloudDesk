# 🚀 Xquantify-MT5-CloudDesk

A **professional, Dockerized** scaffold you can push to GitHub and run anywhere.

## Quick Start

```bash
# 1) Prepare env
cp .env.example .env

# 2) Build & run
docker-compose up --build
```

Then open: http://localhost:8000/ and health at http://localhost:8000/health

## Tech
- Python 3.11, FastAPI, Uvicorn
- Docker & Docker Compose
- PostgreSQL 15

## Structure
```
.
├── Dockerfile
├── docker-compose.yaml
├── requirements.txt
├── main.py
├── .env.example
├── .dockerignore
├── .gitignore
├── README.md
└── LICENSE.md
```

## Notes
- The app port defaults to **8000** (configurable via `APP_PORT`).
- Database connection details are in `.env.example`—adjust as needed.