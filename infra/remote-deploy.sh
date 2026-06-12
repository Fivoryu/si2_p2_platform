#!/usr/bin/env bash
set -euo pipefail

PUBLIC_HOST="${PUBLIC_HOST:?}"
JWT_SECRET="${JWT_SECRET:?}"
WEBHOOK_SECRET="${WEBHOOK_SECRET:-am-prod-secret-min-32-chars-change-me}"
SKIP_OSRM="${SKIP_OSRM:-1}"
REPO_DIR="$HOME/si2_p2_platform"

if ! command -v docker &>/dev/null; then
  sudo dnf install -y docker git
  sudo systemctl enable --now docker
  sudo usermod -aG docker "$USER"
fi

if ! docker compose version &>/dev/null; then
  sudo mkdir -p /usr/local/lib/docker/cli-plugins
  COMPOSE_VER="v2.29.2"
  sudo curl -fsSL "https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-linux-$(uname -m)" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi

if [ ! -d "$REPO_DIR/.git" ]; then
  git clone --recurse-submodules https://github.com/Fivoryu/si2_p2_platform.git "$REPO_DIR"
else
  cd "$REPO_DIR"
  git pull --recurse-submodules
fi
cd "$REPO_DIR"

if [ ! -d infra/acquiremock/.git ]; then
  git clone https://github.com/ashfromsky/acquiremock.git infra/acquiremock
fi

cat > .env.aws <<EOF
PUBLIC_HOST=${PUBLIC_HOST}
JWT_SECRET=${JWT_SECRET}
ACQUIREMOCK_WEBHOOK_SECRET=${WEBHOOK_SECRET}
AWS_REGION=us-east-1
S3_BUCKET_EVIDENCIAS=emergencias-evidencias
EMAIL_PROVIDER=resend
RESEND_API_KEY=
EOF

mkdir -p backend/secrets
if [ -f /tmp/firebase-service-account.json ]; then
  cp /tmp/firebase-service-account.json backend/secrets/firebase-service-account.json
fi

export SKIP_OSRM
if [ -f /tmp/deploy-aws-ec2.sh ]; then
  cp /tmp/deploy-aws-ec2.sh scripts/deploy-aws-ec2.sh
  chmod +x scripts/deploy-aws-ec2.sh
fi
sed -i 's/\r$//' scripts/deploy-aws-ec2.sh scripts/prepare-osrm.sh 2>/dev/null || true
bash scripts/deploy-aws-ec2.sh
