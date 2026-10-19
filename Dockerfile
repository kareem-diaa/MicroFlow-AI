FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt "psycopg[binary]>=3.1" "redis>=5"
COPY . .
RUN python scripts/generate_samples.py \
 && useradd --create-home --uid 10001 appuser && chown -R appuser /app
USER appuser
EXPOSE 8000
# Cloud Run sets $PORT; default 8000 locally
CMD ["sh", "-c", "uvicorn backend.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers"]
