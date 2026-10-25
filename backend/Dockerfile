FROM python:3.12-slim

WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .

# SQLite lives on a volume so data survives container restarts.
ENV BUDGET_DB=/data/budget.db
RUN mkdir /data
VOLUME /data

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
