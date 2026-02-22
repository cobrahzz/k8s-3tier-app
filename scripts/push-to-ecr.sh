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

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

docker build -t "${ECR_REGISTRY}/${ECR_FRONTEND_REPO}:${IMAGE_TAG}" ./services/frontend
docker push "${ECR_REGISTRY}/${ECR_FRONTEND_REPO}:${IMAGE_TAG}"

docker build -t "${ECR_REGISTRY}/${ECR_BACKEND_REPO}:${IMAGE_TAG}" ./services/backend
docker push "${ECR_REGISTRY}/${ECR_BACKEND_REPO}:${IMAGE_TAG}"

echo "Pushed:"
echo "  ${ECR_REGISTRY}/${ECR_FRONTEND_REPO}:${IMAGE_TAG}"
echo "  ${ECR_REGISTRY}/${ECR_BACKEND_REPO}:${IMAGE_TAG}"
