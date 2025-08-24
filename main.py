import os
from fastapi import FastAPI
from pydantic import BaseModel
from typing import Dict
import socket

app = FastAPI(title="Xquantify-MT5-CloudDesk", version="1.0.0")

class HealthResp(BaseModel):
    status: str
    env: str
    hostname: str
    app_port: int

@app.get("/health", response_model=HealthResp)
def health() -> HealthResp:
    return HealthResp(
        status="ok",
        env=os.getenv("APP_ENV", "development"),
        hostname=socket.gethostname(),
        app_port=int(os.getenv("APP_PORT", "8000"))
    )

@app.get("/")
def root() -> Dict[str, str]:
    return {
        "brand": "Xquantify",
        "product": "MT5-CloudDesk",
        "message": "Welcome! Your Dockerized FastAPI service is running."
    }