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

## RBAC fixes required for kube-proxy and kubelet API access
kubectl create clusterrolebinding kube-proxy \
  --clusterrole=system:node-proxier \
  --serviceaccount=kube-system:kube-proxy \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create clusterrolebinding system:kube-apiserver-to-kubelet \
  --clusterrole=system:kubelet-api-admin \
  --user=kube-apiserver-kubelet-client \
  --dry-run=client -o yaml | kubectl apply -f -

if [[ -f ~/ecr-secret.env ]]; then
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

## nginx ingress controller (bare-metal, NodePort)
INGRESS_NS="ingress-nginx"
if ! kubectl get namespace "${INGRESS_NS}" &>/dev/null; then
  echo "Installing nginx ingress controller..."
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/baremetal/deploy.yaml
else
  echo "nginx ingress controller namespace already exists, skipping install."
fi

## Pin ingress controller to onsite workers (cross-cluster routing to cloud pods is unreliable)
kubectl patch deployment ingress-nginx-controller -n "${INGRESS_NS}" --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/affinity","value":{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"topology.kubernetes.io/region","operator":"In","values":["onsite"]}]}]}}}}]'

echo "Waiting for ingress-nginx controller to be ready..."
kubectl rollout status deployment/ingress-nginx-controller -n "${INGRESS_NS}" --timeout=120s

## Patch NodePort to fixed port 30080 so HAProxy always hits the same port
HTTP_NP="$(kubectl get svc ingress-nginx-controller -n "${INGRESS_NS}" \
  -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || true)"
if [[ "${HTTP_NP}" != "30080" ]]; then
  echo "Patching ingress-nginx NodePort to 30080..."
  kubectl patch svc ingress-nginx-controller -n "${INGRESS_NS}" \
    --type='json' \
    -p='[
      {"op":"replace","path":"/spec/ports/0/nodePort","value":30080},
      {"op":"replace","path":"/spec/ports/1/nodePort","value":30443}
    ]'
fi

kubectl apply -f base/ingress/ingress.yaml

## ArgoCD GitOps
ARGOCD_NS="argocd"
if ! kubectl get namespace "${ARGOCD_NS}" &>/dev/null; then
  echo "Installing ArgoCD..."
  kubectl create namespace "${ARGOCD_NS}"
  kubectl apply -n "${ARGOCD_NS}" -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
else
  echo "ArgoCD namespace already exists, skipping install."
fi

echo "Waiting for ArgoCD server to be ready..."
kubectl rollout status deployment/argocd-server -n "${ARGOCD_NS}" --timeout=180s

## Configure argocd-server for HTTP + sub-path /argocd (required for nginx ingress)
## Idempotent: patch is applied even if args already exist (duplicates are harmless)
kubectl patch deployment argocd-server -n "${ARGOCD_NS}" \
  --type='json' \
  -p='[
    {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"},
    {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--rootpath=/argocd"}
  ]' || true

kubectl rollout status deployment/argocd-server -n "${ARGOCD_NS}" --timeout=120s

## Apply ArgoCD ingress + Application manifests (triggers first sync from git)
kubectl apply -f argocd/ingress.yaml
kubectl apply -f argocd/webstore-app.yaml

echo "Done. Checking pods:"
kubectl get pods -n webstore
echo ""
echo "Access the webstore at: http://192.168.1.50"
echo "Access ArgoCD at:       http://192.168.1.50/argocd"
echo "ArgoCD admin password:  $(kubectl get secret argocd-initial-admin-secret -n "${ARGOCD_NS}" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo '(secret not found - may already be deleted)')"
echo ""
echo "NOTE: Run monitoring-install.sh separately to install Prometheus + Grafana"
