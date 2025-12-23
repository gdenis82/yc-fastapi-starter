#!/bin/sh

set -e

echo "DB Connection info:"
echo "SERVER: $POSTGRES_SERVER"
echo "PORT: $POSTGRES_PORT"
echo "USER: $POSTGRES_USER"
echo "DB: $POSTGRES_DB"

echo "Checking DB connectivity to $POSTGRES_SERVER:$POSTGRES_PORT..."
# Wait for DNS resolution
MAX_RETRIES=30
RETRY_COUNT=0
DB_IP=""

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    DB_IP=$(python -c "import socket; print(socket.gethostbyname(\"$POSTGRES_SERVER\"))" 2>/dev/null)
    if [ -n "$DB_IP" ]; then
        echo "Resolved $POSTGRES_SERVER to $DB_IP (attempt $((RETRY_COUNT+1)))"
        break
    fi
    echo "Waiting for DNS resolution of $POSTGRES_SERVER... (attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
    RETRY_COUNT=$((RETRY_COUNT+1))
    sleep 5
done

if [ -z "$DB_IP" ]; then
    echo "Failed to resolve $POSTGRES_SERVER after $MAX_RETRIES attempts."
    # We don't exit here to let alembic/app fail with its own error message, 
    # but at least we've provided diagnostic info.
fi

echo "Running migrations..."
alembic upgrade head

echo "Starting application..."
exec gunicorn app.main:app --workers 4 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000 --access-logfile - --error-logfile -
