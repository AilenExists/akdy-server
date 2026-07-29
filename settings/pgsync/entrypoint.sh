#!/bin/bash
set -e

# bootstrap은 이미 수행된 경우 재실행해도 안전하게 스킵되지만,
# 명시적으로 마커 파일로 관리하면 더 예측 가능
if [ ! -f /app/.bootstrapped ]; then
  echo "Running bootstrap..."
  bootstrap --config /app/schema.json
  touch /app/.bootstrapped
fi

echo "Starting pgsync daemon..."
exec pgsync --config /app/schema.json --daemon