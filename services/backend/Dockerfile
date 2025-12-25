FROM python:3.12-slim

RUN apt-get update && apt-get install -y \
    netcat-openbsd \
    dnsutils \
    curl \
    ca-certificates \
    wget \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Download Yandex Cloud CA certificate for PostgreSQL
RUN mkdir -p /root/.postgresql && \
    wget "https://storage.yandexcloud.net/cloud-certs/CA.pem" \
         --output-document /root/.postgresql/root.crt && \
    chmod 0600 /root/.postgresql/root.crt

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . /app/
ENV PYTHONPATH=/app

RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]