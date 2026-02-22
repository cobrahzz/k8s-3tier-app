#!/usr/bin/env bash
# Install Prometheus + Grafana (kube-prometheus-stack) via Helm.
# Run this once manually — it is NOT called by deploy.sh.
# Re-run to upgrade. CRDs are applied one-by-one to tolerate slow etcd (HDD).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES="${SCRIPT_DIR}/monitoring/values-kube-prometheus-stack.yaml"

## Install helm if missing
if ! command -v helm &>/dev/null; then
  echo "Installing helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

## Pull chart and apply CRDs one-by-one (avoids etcd large-write timeouts on HDD)
echo "Pulling kube-prometheus-stack chart..."
rm -rf /tmp/kube-prom
helm pull prometheus-community/kube-prometheus-stack --untar --untardir /tmp/kube-prom

echo "Applying CRDs individually..."
for crd in /tmp/kube-prom/kube-prometheus-stack/charts/crds/crds/*.yaml; do
  echo "  $(basename "${crd}")"
  kubectl apply --server-side --force-conflicts -f "${crd}"
done
rm -rf /tmp/kube-prom

## Install / upgrade the chart (CRDs already applied above)
echo "Installing kube-prometheus-stack..."
helm upgrade --install kube-prom-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f "${VALUES}" \
  --timeout 300s \
  --wait \
  --skip-crds

echo ""
echo "Access Grafana at: http://192.168.1.50/grafana  (admin / admin123)"
