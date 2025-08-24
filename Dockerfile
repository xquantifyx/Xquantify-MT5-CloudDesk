# ------------ Base Image ------------
FROM python:3.11-slim AS base

# System setup
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PIP_NO_CACHE_DIR=1

# Workdir
WORKDIR /app

# System deps (only what's needed)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \    gcc \    libpq-dev \    && rm -rf /var/lib/apt/lists/*

# Python deps
COPY requirements.txt .
RUN pip install -r requirements.txt

# Copy app
COPY . .

# Non-root user (safer)
RUN useradd -m appuser && chown -R appuser:appuser /app
USER appuser

# Expose app port (documentational)
EXPOSE 8000

# Default command (can be overridden by compose)
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]