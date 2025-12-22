FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    netcat-openbsd \
    dnsutils \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV PYTHONPATH=/app

RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]