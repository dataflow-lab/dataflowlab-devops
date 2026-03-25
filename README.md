# DataFlowLab DevOps

Centralized infrastructure for the DataFlowLab suite — a cryptocurrency data streaming and analytics platform.

## Related Projects

| Project                                                     | Description                                                           |
|-------------------------------------------------------------|-----------------------------------------------------------------------|
| [coingecko-source-connector](../coingecko-source-connector) | Kafka Connect source connector for CoinGecko API                      |
| [crypto-streams-analytics](../crypto-streams-analytics)     | Kafka Streams real-time analytics (volatility, tiering, depeg alerts) |

## Quick Start

```bash
cd docker

# Create .env from template and fill in your credentials
cp .env.example .env

# Start the full stack
docker compose --profile full-cluster up -d

# Build and deploy the CoinGecko connector plugin
./connect/deploy-connector.sh

# Register the connector (after kafka-connect is healthy)
./connect/register-coingecko-source.sh
```

### Profiles

| Profile        | Description                                                                  |
|----------------|------------------------------------------------------------------------------|
| `full-cluster` | All services: 3 Connect nodes, 2 Schema Registry nodes, Kibana, Dejavu, etc. |
| `mini-cluster` | Minimal set: 1 Connect node, 1 Schema Registry node, no Kibana/Dejavu        |

```bash
docker compose --profile full-cluster up -d   # everything
docker compose --profile mini-cluster up -d   # lightweight
```

### Running with crypto-streams-analytics

Build the Docker image first, then start the stack:

```bash
# Build the analytics app image
cd ../../crypto-streams-analytics
./build-image.sh

# Start with the analytics app (included in both profiles)
cd ../dataflowlab-devops/docker
docker compose --profile mini-cluster up -d
```

## Services

| Service                  | Port                | Profile | Description                          |
|--------------------------|---------------------|---------|--------------------------------------|
| Kafka (x3)               | 19092, 19094, 19096 | both    | KRaft cluster (no Zookeeper)         |
| Schema Registry 1        | 18081               | both    | Confluent Avro schema registry       |
| Schema Registry 2        | 18082               | full    | Schema Registry replica              |
| Kafka Connect 1          | 18083               | both    | CoinGecko source + plugin connectors |
| Kafka Connect 2/3        | 18084, 18085        | full    | Connect cluster replicas             |
| Conduktor Console        | 18088               | both    | Kafka management UI                  |
| PostgreSQL               | 5433                | both    | General-purpose database             |
| Elasticsearch            | 9200                | both    | Search and analytics engine          |
| Kibana                   | 5601                | full    | Elasticsearch UI                     |
| Dejavu                   | 1358                | full    | Elasticsearch data browser           |
| crypto-streams-analytics | 8085                | both    | Kafka Streams analytics app          |

## Kafka Connect

### CoinGecko Source Connector

Deploy and register the connector:

```bash
# Deploy plugin to Connect cluster
./connect/deploy-connector.sh

# Register connector instance
./connect/register-coingecko-source.sh
```

The connector config is in `connect/coingecko-markets-source.json` (for reference/Postman import). The registration
script reads credentials from `.env` and injects them automatically.

### Managing Connectors

```bash
# Status
curl -s http://localhost:18083/connectors/coingecko-source/status | python3 -m json.tool

# Pause / Resume / Delete
curl -X PUT http://localhost:18083/connectors/coingecko-source/pause
curl -X PUT http://localhost:18083/connectors/coingecko-source/resume
curl -X DELETE http://localhost:18083/connectors/coingecko-source

# Logs
docker logs -f kafka-connect-1-local
```

## Directory Structure

```
docker/
├── docker-compose.yml              # Full stack: Kafka + Connect + monitoring + apps
├── .env.example                    # Environment template (committed to git)
├── .env                            # Real credentials (git-ignored)
├── migrate-volumes.sh              # One-time volume migration from kafka-connect-demo
├── connect/
│   ├── deploy-connector.sh         # Build & deploy connector plugin to Connect cluster
│   ├── register-coingecko-source.sh # Register CoinGecko source connector
│   └── coingecko-markets-source.json # Connector config (for reference/Postman)
└── datagen/
    └── person.avsc                 # Avro schema for DataGen connector testing
```
