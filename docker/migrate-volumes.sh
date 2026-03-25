#!/bin/bash
# One-time migration script to copy Docker volume data from the old project
# (kafka-connect-demo) to the new project (dataflowlab).
#
# Usage:
#   ./migrate-volumes.sh           # interactive (prompts for confirmation)
#   ./migrate-volumes.sh --dry-run # show what would be done without doing it
#
# Prerequisites:
#   - Old containers must be stopped (docker compose -p kafka-connect-demo down)
#   - New stack must NOT be running yet

set -euo pipefail

OLD_PREFIX="kafka-connect-demo"
NEW_PREFIX="dataflowlab"

VOLUMES=(
  "kafka-1-data-local"
  "kafka-2-data-local"
  "kafka-3-data-local"
  "cdk_pg_data-local"
  "conduktor_data-local"
)

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
  echo "=== DRY RUN MODE ==="
  echo ""
fi

echo "This script migrates Docker volumes from '${OLD_PREFIX}' to '${NEW_PREFIX}'."
echo ""
echo "Volumes to migrate:"
for vol in "${VOLUMES[@]}"; do
  OLD_VOL="${OLD_PREFIX}_${vol}"
  NEW_VOL="${NEW_PREFIX}_${vol}"
  OLD_EXISTS=$(docker volume ls -q --filter "name=^${OLD_VOL}$" 2>/dev/null)
  if [ -n "$OLD_EXISTS" ]; then
    echo "  ${OLD_VOL} -> ${NEW_VOL}"
  else
    echo "  ${OLD_VOL} -> (NOT FOUND, skipping)"
  fi
done

echo ""
if [ "$DRY_RUN" = true ]; then
  echo "Dry run complete. No changes were made."
  exit 0
fi

read -p "Proceed with migration? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

MIGRATED=0
SKIPPED=0

for vol in "${VOLUMES[@]}"; do
  OLD_VOL="${OLD_PREFIX}_${vol}"
  NEW_VOL="${NEW_PREFIX}_${vol}"

  # Check if old volume exists
  if ! docker volume ls -q --filter "name=^${OLD_VOL}$" 2>/dev/null | grep -q .; then
    echo "SKIP: ${OLD_VOL} does not exist."
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Check if new volume already exists
  if docker volume ls -q --filter "name=^${NEW_VOL}$" 2>/dev/null | grep -q .; then
    echo "SKIP: ${NEW_VOL} already exists (won't overwrite)."
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo "Migrating ${OLD_VOL} -> ${NEW_VOL}..."

  # Create new volume
  docker volume create "$NEW_VOL" > /dev/null

  # Copy data using a temporary Alpine container
  docker run --rm \
    -v "${OLD_VOL}:/source:ro" \
    -v "${NEW_VOL}:/dest" \
    alpine \
    sh -c 'cp -a /source/. /dest/'

  echo "  Done."
  MIGRATED=$((MIGRATED + 1))
done

echo ""
echo "=== Migration complete ==="
echo "  Migrated: ${MIGRATED}"
echo "  Skipped:  ${SKIPPED}"
echo ""
echo "You can now start the new stack:"
echo "  docker compose up -d"
echo ""
echo "Once verified, you can remove old volumes with:"
echo "  docker volume rm ${OLD_PREFIX}_kafka-1-data-local ${OLD_PREFIX}_kafka-2-data-local ${OLD_PREFIX}_kafka-3-data-local ${OLD_PREFIX}_cdk_pg_data-local ${OLD_PREFIX}_conduktor_data-local"
