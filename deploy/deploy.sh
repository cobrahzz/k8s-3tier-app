#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

kubectl apply -f base/namespaces.yaml

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
