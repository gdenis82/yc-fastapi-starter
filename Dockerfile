FROM python:3.12-slim

RUN apt-get update && apt-get install -y \
    netcat-openbsd \
    dnsutils \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Download Yandex Cloud CA certificate
RUN mkdir -p /usr/local/share/ca-certificates/Yandex && \
    curl -sSL https://storage.yandexcloud.net/cloud-certs/CA.pem -o /usr/local/share/ca-certificates/Yandex/YandexInternalRootCA.crt && \
    update-ca-certificates

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV PYTHONPATH=/app

RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]