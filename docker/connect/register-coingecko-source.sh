#!/bin/bash
# Register CoinGecko Source Connector to poll market data from CoinGecko API.
# Run this ONCE after kafka-connect container is healthy and the connector JAR is deployed.
#
# Usage: ./register-coingecko-source.sh [CONNECT_HOST]
#   CONNECT_HOST defaults to localhost:18083
#
# Reads from ../.env (or expects environment variables):
#   COINGECKO_API_KEY              (required)
#   SCHEMA_REGISTRY_URL_INTERNAL   (optional, defaults to http://schema-registry-local:8081)

CONNECT_HOST="${1:-localhost:18083}"

# Load .env if present
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

: "${COINGECKO_API_KEY:?COINGECKO_API_KEY is not set. Export it or add to .env}"
: "${SCHEMA_REGISTRY_URL_INTERNAL:=http://schema-registry-local:8081}"

echo "Waiting for Kafka Connect to be ready..."
until curl -s -o /dev/null -w "%{http_code}" "http://${CONNECT_HOST}/connectors" | grep -q "200"; do
    echo "  Kafka Connect not ready yet, retrying in 5s..."
    sleep 5
done
echo "Kafka Connect is ready."

echo "Registering coingecko-source connector..."

curl -X POST "http://${CONNECT_HOST}/connectors" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "coingecko-source",
    "config": {
      "connector.class": "com.stitch80.connect.coingecko.CoinGeckoSourceConnector",
      "tasks.max": "1",

      "coingecko.api.key": "'"${COINGECKO_API_KEY}"'",
      "coingecko.coin.ids": "bitcoin,ethereum,solana",
      "coingecko.vs.currency": "usd",
      "coingecko.topic.prefix": "raw.coingecko",
      "coingecko.poll.interval.ms": "60000",
      "coingecko.endpoints": "markets,simple_price,coin_detail",
      "coingecko.markets.per.page": "250",
      "coingecko.rate.limit.calls.per.minute": "25",
      "coingecko.request.timeout.ms": "30000",
      "coingecko.coin.detail.poll.interval.ms": "3600000",

      "key.converter": "org.apache.kafka.connect.storage.StringConverter",
      "value.converter": "io.confluent.connect.avro.AvroConverter",
      "value.converter.schema.registry.url": "'"${SCHEMA_REGISTRY_URL_INTERNAL}"'"
    }
  }'

echo ""
echo ""
echo "Checking connector status..."
sleep 2

echo "=== coingecko-source ==="
curl -s "http://${CONNECT_HOST}/connectors/coingecko-source/status" | python3 -m json.tool 2>/dev/null || \
curl -s "http://${CONNECT_HOST}/connectors/coingecko-source/status"

echo ""
echo "Done. CoinGecko source connector registered."
