#!/bin/sh
# Start the API; once it answers, make sure the demo account exists (the
# login screen offers it). The database is ephemeral on free hosting, so this
# runs on every start. If the account already has data (a persistent volume)
# the seed script declines, which is fine.
PORT="${PORT:-8000}"
uvicorn main:app --host 0.0.0.0 --port "$PORT" &
SERVER=$!
for i in $(seq 1 30); do
  if python -c "import urllib.request as u; u.urlopen('http://127.0.0.1:$PORT/docs', timeout=2)" >/dev/null 2>&1; then
    python seed_demo.py --api "http://127.0.0.1:$PORT" >/dev/null 2>&1 || true
    break
  fi
  sleep 1
done
wait $SERVER
