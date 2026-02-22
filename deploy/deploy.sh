#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if ! kubectl get storageclass local-path &>/dev/null; then
  echo "Installing local-path-provisioner..."
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
fi

if [[ "$(kubectl get storageclass local-path -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null)" != "true" ]]; then
  kubectl patch storageclass local-path \
    -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
fi

kubectl apply -f base/namespaces.yaml

if [[ -f ~/ecr-secret.env ]] && [[ ! -f "${SCRIPT_DIR}/ecr-secret.env" ]]; then
  mv ~/ecr-secret.env "${SCRIPT_DIR}/ecr-secret.env"
fi

if [[ -f "${SCRIPT_DIR}/ecr-secret.env" ]]; then
  source "${SCRIPT_DIR}/ecr-secret.env"
  kubectl create secret docker-registry ecr-secret \
    --namespace webstore \
    --docker-server="${ECR_REGISTRY}" \
    --docker-username=AWS \
    --docker-password="${ECR_TOKEN}" \
    --save-config \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "ECR pull secret refreshed."
else
  echo "Warning: deploy/ecr-secret.env not found. Skipping ECR secret creation."
  echo "Run scripts/push-to-ecr.sh on your desktop first, then copy deploy/ecr-secret.env here."
fi

kubectl apply -f base/postgres/secret.yaml
kubectl apply -f base/postgres/pvc.yaml
kubectl apply -f base/postgres/statefulset.yaml
kubectl apply -f base/postgres/service.yaml

kubectl apply -f base/backend/configmap.yaml
kubectl apply -f base/backend/service.yaml
kubectl apply -f base/backend/deploy-onsite.yaml
kubectl apply -f base/backend/deploy-cloud.yaml

kubectl apply -f base/frontend/service.yaml
kubectl apply -f base/frontend/deploy-onsite.yaml
kubectl apply -f base/frontend/deploy-cloud.yaml

kubectl apply -f base/ingress/ingress.yaml

echo "Done. Checking pods:"
kubectl get pods -n webstore
