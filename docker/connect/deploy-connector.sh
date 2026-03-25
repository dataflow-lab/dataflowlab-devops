#!/bin/bash
# Build the CoinGecko source connector fat JAR, copy it into the kafka-connect
# Docker containers, restart Connect, and verify the plugin is loaded.
#
# Usage: ./deploy-connector.sh [CONNECT_CONTAINERS] [CONNECT_HOST]
#   CONNECT_CONTAINERS  space-separated list (default: "kafka-connect-1-local kafka-connect-2-local kafka-connect-3-local")
#   CONNECT_HOST        defaults to localhost:18083
#
# Environment:
#   CONNECTOR_PROJECT_DIR  path to the coingecko-source-connector project
#                          (default: ../../../coingecko-source-connector)
#
# Prerequisites:
#   - The kafka-connect containers must be running
#
# After this script finishes, register the connector:
#   ./register-coingecko-source.sh

set -euo pipefail

CONNECT_CONTAINERS="${1:-kafka-connect-1-local kafka-connect-2-local kafka-connect-3-local}"
CONNECT_HOST="${2:-localhost:18083}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECTOR_PROJECT_DIR="${CONNECTOR_PROJECT_DIR:-${SCRIPT_DIR}/../../../coingecko-source-connector}"
PLUGIN_NAME="stitch80-kafka-connect-coingecko"
PLUGIN_DIR="/usr/share/confluent-hub-components/$PLUGIN_NAME"

# Resolve to absolute path
CONNECTOR_PROJECT_DIR="$(cd "$CONNECTOR_PROJECT_DIR" && pwd)"

# ── 1. Build ────────────────────────────────────────────────────────────────
echo "==> Building connector plugin in $CONNECTOR_PROJECT_DIR..."
cd "$CONNECTOR_PROJECT_DIR"
./gradlew clean connectPlugin --quiet

LOCAL_PLUGIN="$CONNECTOR_PROJECT_DIR/build/connect-plugin/$PLUGIN_NAME"
if [ ! -d "$LOCAL_PLUGIN" ]; then
  echo "ERROR: Plugin directory not found at $LOCAL_PLUGIN"
  exit 1
fi
echo "    Built plugin contents:"
ls -lh "$LOCAL_PLUGIN"

# ── 2. Deploy plugin to each Connect container ───────────────────────────────
for CONNECT_CONTAINER in $CONNECT_CONTAINERS; do
  echo ""
  echo "==> Deploying to $CONNECT_CONTAINER..."

  if ! docker inspect -f '{{.State.Running}}' "$CONNECT_CONTAINER" 2>/dev/null | grep -q true; then
    echo "WARNING: Container '$CONNECT_CONTAINER' is not running, skipping."
    continue
  fi

  echo "    Removing old plugin (if any)..."
  docker exec "$CONNECT_CONTAINER" rm -rf "$PLUGIN_DIR" 2>/dev/null || true

  echo "    Copying plugin directory to $CONNECT_CONTAINER:$PLUGIN_DIR/"
  docker cp "$LOCAL_PLUGIN" "$CONNECT_CONTAINER:$PLUGIN_DIR"

  echo "    Verifying plugin in container..."
  docker exec "$CONNECT_CONTAINER" ls -lhR "$PLUGIN_DIR"
done

# ── 3. Restart all Connect containers to pick up the new plugin ──────────────
echo ""
echo "==> Restarting Connect containers..."
for CONNECT_CONTAINER in $CONNECT_CONTAINERS; do
  if docker inspect -f '{{.State.Running}}' "$CONNECT_CONTAINER" 2>/dev/null | grep -q true; then
    echo "    Restarting $CONNECT_CONTAINER..."
    docker restart "$CONNECT_CONTAINER"
  fi
done

echo "==> Waiting for Kafka Connect to be ready..."
until curl -s -o /dev/null -w "%{http_code}" "http://${CONNECT_HOST}/connectors" 2>/dev/null | grep -q "200"; do
    echo "    Not ready yet, retrying in 5s..."
    sleep 5
done
echo "    Kafka Connect is ready."

# ── 4. Verify plugin is loaded ──────────────────────────────────────────────
echo "==> Checking installed connector plugins..."
if curl -s "http://${CONNECT_HOST}/connector-plugins" 2>/dev/null | grep -q "CoinGeckoSourceConnector"; then
  echo "    ✓ CoinGeckoSourceConnector plugin found"
else
  echo "    ✗ CoinGeckoSourceConnector NOT found in plugin list."
  echo "      Available plugins:"
  curl -s "http://${CONNECT_HOST}/connector-plugins" | python3 -m json.tool 2>/dev/null || \
  curl -s "http://${CONNECT_HOST}/connector-plugins"
  echo ""
  echo "      Check container logs: docker logs $CONNECT_CONTAINER"
  exit 1
fi

echo ""
echo "=== Deployment complete ==="
echo "  Containers: $CONNECT_CONTAINERS"
echo "  Plugin dir: $PLUGIN_DIR"
echo "  Connect:    http://$CONNECT_HOST"
echo ""
echo "Next step — register the connector:"
echo "  ./register-coingecko-source.sh $CONNECT_HOST"
echo ""
echo "Useful commands:"
echo "  Status:     curl -s http://$CONNECT_HOST/connectors/coingecko-source/status | python3 -m json.tool"
echo "  Pause:      curl -X PUT http://$CONNECT_HOST/connectors/coingecko-source/pause"
echo "  Resume:     curl -X PUT http://$CONNECT_HOST/connectors/coingecko-source/resume"
echo "  Delete:     curl -X DELETE http://$CONNECT_HOST/connectors/coingecko-source"
echo "  Logs:       docker logs -f kafka-connect-1-local"
