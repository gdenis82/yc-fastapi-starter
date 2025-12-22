#!/bin/sh

set -e

echo "Checking DB connectivity to $POSTGRES_SERVER:$POSTGRES_PORT..."
# Try to resolve hostname for diagnostic
python -c "import socket; print(f'Resolved $POSTGRES_SERVER to {socket.gethostbyname(\"$POSTGRES_SERVER\")}')" || echo "Failed to resolve $POSTGRES_SERVER"

echo "Running migrations..."
alembic upgrade head

echo "Starting application..."
exec gunicorn app.main:app --workers 4 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000 --access-logfile - --error-logfile -
