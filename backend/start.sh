#!/bin/sh
# Start the API; once it answers, make sure the demo account exists (the
# login screen offers it). The database is ephemeral on free hosting, so this
# runs on every start and does nothing if the account already has data.
PORT="${PORT:-8000}"
uvicorn main:app --host 0.0.0.0 --port "$PORT" &
SERVER=$!
for i in $(seq 1 30); do
  python seed_demo.py --api "http://127.0.0.1:$PORT" >/dev/null 2>&1 && break
  sleep 1
done
wait $SERVER
