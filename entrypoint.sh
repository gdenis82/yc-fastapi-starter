#!/bin/sh

set -e

echo "Checking DB connectivity..."
# Try to connect to DB port with timeout
for i in $(seq 1 30); do
  if nc -zv $POSTGRES_SERVER $POSTGRES_PORT; then
    echo "DB is up!"
    break
  else
    echo "Waiting for DB ($POSTGRES_SERVER:$POSTGRES_PORT)..."
    sleep 2
  fi
done

echo "Running migrations..."
alembic upgrade head

echo "Starting application..."
exec gunicorn app.main:app --workers 4 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000 --access-logfile - --error-logfile -
