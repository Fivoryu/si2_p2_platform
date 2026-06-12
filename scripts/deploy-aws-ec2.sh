#!/usr/bin/env bash
# Bootstrap despliegue en EC2 (Amazon Linux 2023).
# Ejecutar como ec2-user tras crear la instancia con IAM role S3.
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/Fivoryu/si2_p2_platform.git}"
ACQUIREMOCK_URL="${ACQUIREMOCK_URL:-https://github.com/ashfromsky/acquiremock.git}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/si2_p2_platform}"
SKIP_OSRM="${SKIP_OSRM:-0}"

docker_cmd() {
  if docker info >/dev/null 2>&1; then
    docker "$@"
  else
    sudo docker "$@"
  fi
}

echo "=== Instalando Docker ==="
if ! command -v docker &>/dev/null; then
  sudo dnf install -y docker git
  sudo systemctl enable --now docker
  sudo usermod -aG docker "$USER"
  echo "Docker instalado. Si falla permisos, ejecuta: newgrp docker"
fi

if ! docker_cmd compose version &>/dev/null; then
  sudo mkdir -p /usr/local/lib/docker/cli-plugins
  COMPOSE_VER="v2.29.2"
  sudo curl -fsSL "https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-linux-$(uname -m)" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi

echo "=== Clonando plataforma ==="
if [ ! -d "$INSTALL_DIR/.git" ]; then
  git clone --recurse-submodules "$REPO_URL" "$INSTALL_DIR"
else
  cd "$INSTALL_DIR"
  git pull --recurse-submodules
fi
cd "$INSTALL_DIR"

echo "=== Clonando AcquireMock ==="
if [ ! -d infra/acquiremock/.git ]; then
  git clone "$ACQUIREMOCK_URL" infra/acquiremock
fi

if [ ! -f .env.aws ]; then
  echo "ERROR: Crea .env.aws desde .env.aws.example con PUBLIC_HOST y secretos."
  echo "  cp .env.aws.example .env.aws && nano .env.aws"
  exit 1
fi

# shellcheck disable=SC1091
set -a
source .env.aws
set +a

echo "=== Verificando bucket S3 ==="
aws s3 mb "s3://${S3_BUCKET_EVIDENCIAS:-emergencias-evidencias}" 2>/dev/null || true

if [ "$SKIP_OSRM" != "1" ]; then
  echo "=== Preparando OSRM (puede tardar 10-15 min) ==="
  bash scripts/prepare-osrm.sh
else
  echo "SKIP_OSRM=1 — usando fallback público OSRM"
fi

echo "=== Firebase secrets (opcional) ==="
if [ ! -f backend/secrets/firebase-service-account.json ]; then
  echo "AVISO: Falta backend/secrets/firebase-service-account.json (push notifications)."
fi

echo "=== Levantando stack ==="
docker_cmd compose -f docker-compose.yml -f docker-compose.aws.yml --env-file .env.aws up -d --build

echo "=== Esperando health checks ==="
for i in $(seq 1 30); do
  if curl -sf "http://localhost:8000/health" >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

echo ""
echo "=== Verificación ==="
curl -sf "http://localhost:8000/health" && echo " backend OK" || echo " backend FAIL"
curl -sf "http://localhost:8001/health" && echo " acquiremock OK" || echo " acquiremock FAIL"
curl -sf "http://localhost:80" >/dev/null && echo " web OK" || echo " web FAIL"

echo ""
echo "URLs públicas (reemplaza con tu Elastic IP):"
echo "  Web:    http://${PUBLIC_HOST}"
echo "  API:    http://${PUBLIC_HOST}:8000/docs"
echo "  Pagos:  http://${PUBLIC_HOST}:8001"
echo ""
echo "Mobile APK:"
echo "  flutter build apk --release --dart-define=API_URL=http://${PUBLIC_HOST}:8000 --dart-define=WS_URL=ws://${PUBLIC_HOST}:8000"
