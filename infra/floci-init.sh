#!/usr/bin/env bash
# Provisiona recursos en Floci (local o dentro de Docker).
# Uso local:  bash infra/floci-init.sh
# En Docker: lo ejecuta el servicio floci-init de docker-compose.yml

set -e

EP="${AWS_ENDPOINT_URL:-http://localhost:4566}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="$REGION"

echo "Floci endpoint: $EP"

until aws s3 ls --endpoint-url "$EP" >/dev/null 2>&1; do
  echo "Waiting for Floci..."
  sleep 2
done

aws s3 mb "s3://emergencias-evidencias" --endpoint-url "$EP" 2>/dev/null || true
aws s3 mb "s3://emergencias-web" --endpoint-url "$EP" 2>/dev/null || true
aws sns create-topic --name emergencias-push --endpoint-url "$EP" 2>/dev/null || true

echo "Buckets:"
aws s3 ls --endpoint-url "$EP"
echo "Floci resources ready."
