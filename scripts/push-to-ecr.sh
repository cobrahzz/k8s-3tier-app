#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."
ENV_FILE=".env"

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  source "${ENV_FILE}"
  set +a
fi

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-YOUR_AWS_ACCOUNT_ID}"
AWS_REGION="${AWS_REGION:-YOUR_AWS_REGION}"
ECR_FRONTEND_REPO="${ECR_FRONTEND_REPO:-YOUR_ECR_FRONTEND_REPO}"
ECR_BACKEND_REPO="${ECR_BACKEND_REPO:-YOUR_ECR_BACKEND_REPO}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
AWS_PROFILE="${AWS_PROFILE:-}"
CONTROL_PLANE_HOST="${CONTROL_PLANE_HOST:-}"
CONTROL_PLANE_USER="${CONTROL_PLANE_USER:-remi}"
CONTROL_PLANE_DEPLOY_DIR="${CONTROL_PLANE_DEPLOY_DIR:-~/k8s-3tier-app/deploy}"

AWS_ARGS=("--region" "${AWS_REGION}")
if [[ -n "${AWS_PROFILE}" ]]; then
  AWS_ARGS+=("--profile" "${AWS_PROFILE}")
fi

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

aws ecr get-login-password "${AWS_ARGS[@]}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

docker build -t "${ECR_REGISTRY}/${ECR_FRONTEND_REPO}:${IMAGE_TAG}" ./services/frontend
docker push "${ECR_REGISTRY}/${ECR_FRONTEND_REPO}:${IMAGE_TAG}"

docker build -t "${ECR_REGISTRY}/${ECR_BACKEND_REPO}:${IMAGE_TAG}" ./services/backend
docker push "${ECR_REGISTRY}/${ECR_BACKEND_REPO}:${IMAGE_TAG}"

echo "Pushed:"
echo "  ${ECR_REGISTRY}/${ECR_FRONTEND_REPO}:${IMAGE_TAG}"
echo "  ${ECR_REGISTRY}/${ECR_BACKEND_REPO}:${IMAGE_TAG}"

ECR_TOKEN=$(aws ecr get-login-password "${AWS_ARGS[@]}")
cat > deploy/ecr-secret.env <<EOF
ECR_REGISTRY=${ECR_REGISTRY}
ECR_TOKEN=${ECR_TOKEN}
EOF
echo "ECR token written to deploy/ecr-secret.env"

if [[ -n "${CONTROL_PLANE_HOST}" ]]; then
  scp deploy/ecr-secret.env "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOST}:~/ecr-secret.env"
  echo "ECR token transferred to ${CONTROL_PLANE_HOST}:~/ecr-secret.env"
else
  echo "Tip: set CONTROL_PLANE_HOST in .env to auto-transfer the token to your control plane."
fi

