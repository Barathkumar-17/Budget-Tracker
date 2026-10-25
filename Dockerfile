# API image for hosts that build from the repository root (e.g. a Render
# service with the default settings). Same image as backend/Dockerfile, but
# with the repo root as the build context. The web app has its own
# Dockerfile in app/.
FROM python:3.12-slim

WORKDIR /srv
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/main.py backend/seed_demo.py ./

# SQLite lives in /data (a volume locally; ephemeral on free hosting tiers).
ENV BUDGET_DB=/data/budget.db
RUN mkdir /data
VOLUME /data

# Hosts like Render pass the port in $PORT; default to 8000 locally.
EXPOSE 8000
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}"]
