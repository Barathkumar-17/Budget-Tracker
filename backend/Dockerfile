FROM python:3.12-slim

WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py seed_demo.py ./

# SQLite lives on a volume so data survives container restarts.
ENV BUDGET_DB=/data/budget.db
RUN mkdir /data
VOLUME /data

# Hosts like Render pass the port in $PORT; default to 8000 locally.
EXPOSE 8000
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}"]
