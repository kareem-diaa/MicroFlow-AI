#!/usr/bin/env sh
# Starts the API (port 8000) and dashboard (port 8501) for a local demo.
set -e
pip install -r requirements.txt
python scripts/generate_samples.py
uvicorn backend.main:app --port 8000 &
API_PID=$!
trap 'kill $API_PID' EXIT
sleep 3
streamlit run frontend/app.py --server.port 8501
