# k8s-3tier-app

A simple Amazon-like webstore built as a 3-tier application, containerized with Docker, and deployed on Kubernetes. Images are pushed to AWS ECR using a local shell script. Includes a Prometheus + Grafana monitoring stack.

---

## What it does

- Browse a product catalog and add items to a personal basket
- Create or switch accounts by entering a username (no password required)
- Each user's basket is persisted in PostgreSQL
- Clicking **Buy** validates the order and clears the basket from the database

---

## Architecture

```
Browser
  └── Nginx (Frontend)          serves static HTML/CSS/JS
        └── /api/* proxied to ──► FastAPI (Backend)
                                      └── PostgreSQL (StatefulSet)

Kubernetes Ingress
  ├── /api  ──► backend Service  (port 8000)
  └── /     ──► frontend Service (port 80)

Monitoring (namespace: monitoring)
  └── kube-prometheus-stack (Helm)
        ├── Prometheus  node + cluster metrics (nodeExporter, kubeStateMetrics)
        └── Grafana     NodePort 32000
```

### Deployment topology

| Deployment | Replicas | Nodes |
|---|---|---|
| `frontend-onsite` | 2 | worker1–4 (`topology.kubernetes.io/region=onsite`) |
| `frontend-cloud` | 1 | worker5–6 (`topology.kubernetes.io/region=cloud`) |
| `backend-onsite` | 2 | worker1–4 (`topology.kubernetes.io/region=onsite`) |
| `backend-cloud` | 1 | worker5–6 (`topology.kubernetes.io/region=cloud`) |
| `postgres` (StatefulSet) | 1 | any |

### Resource limits per pod

| Pod | RAM request | RAM limit | CPU request | CPU limit |
|---|---|---|---|---|
| Frontend (Nginx) | 32Mi | 128Mi | 50m | 200m |
| Backend (FastAPI) | 128Mi | 256Mi | 100m | 500m |
| Postgres | 256Mi | 512Mi | 250m | 500m |

---

## Project structure

```
k8s-3tier-app/
├── .env                            Your local config — never committed (git-ignored)
├── .env.example                    Reference template — committed, safe to share
├── .gitignore
├── docker-compose.yml              Local development stack
├── scripts/
│   └── push-to-ecr.sh             Builds and pushes images to your own AWS ECR
├── services/
│   ├── frontend/
│   │   ├── Dockerfile
│   │   ├── nginx.conf             Serves static files + proxies /api/ to backend
│   │   └── src/
│   │       ├── index.html
│   │       ├── styles.css
│   │       └── app.js
│   └── backend/
│       ├── Dockerfile
│       ├── requirements.txt       fastapi, uvicorn, psycopg
│       └── app/
│           └── main.py            All API endpoints + DB init + product seeding
└── deploy/
    ├── deploy.sh                  Deploys everything to the cluster in the correct order
    ├── base/
    │   ├── namespaces.yaml        webstore + monitoring namespaces
    │   ├── postgres/
    │   │   ├── secret.yaml        DB credentials
    │   │   ├── pvc.yaml           5Gi persistent volume claim
    │   │   ├── statefulset.yaml
    │   │   └── service.yaml       Headless service
    │   ├── backend/
    │   │   ├── configmap.yaml     Non-secret env vars
    │   │   ├── service.yaml
    │   │   ├── deploy-onsite.yaml 2 replicas — worker1-4
    │   │   └── deploy-cloud.yaml  1 replica  — worker5-6
    │   ├── frontend/
    │   │   ├── service.yaml
    │   │   ├── deploy-onsite.yaml 2 replicas — worker1-4
    │   │   └── deploy-cloud.yaml  1 replica  — worker5-6
    │   └── ingress/
    │       └── ingress.yaml       nginx ingress class
    └── monitoring/
        └── values-kube-prometheus-stack.yaml
```

> **Control plane:** only the `deploy/` folder is needed. Use sparse checkout to avoid cloning the full repo (see below).

---

## Database schema

| Table | Columns |
|---|---|
| `users` | `id SERIAL PK`, `username VARCHAR UNIQUE` |
| `products` | `id SERIAL PK`, `name VARCHAR`, `price NUMERIC`, `emoji VARCHAR` |
| `basket_items` | `id SERIAL PK`, `user_id FK`, `product_id FK`, `quantity INT`, `UNIQUE(user_id, product_id)` |

8 products are seeded automatically on first backend startup.

---

## API endpoints

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/users/switch` | Create or switch to a user by username |
| `GET` | `/api/products` | List all products |
| `POST` | `/api/basket/{user_id}/add` | Add a product to the basket (increments qty if already present) |
| `GET` | `/api/basket/{user_id}` | Get basket contents and total price |
| `POST` | `/api/basket/{user_id}/checkout` | Validate order and wipe basket |
| `GET` | `/api/health` | Health check — returns `{status, db}` |

---

## Local development

**Requirements:** Docker + Docker Compose

```bash
docker compose up --build
```

Open [http://localhost](http://localhost). The frontend proxies `/api/` to the backend container. The backend retries the database connection on startup (up to 10 attempts, 3 s apart).

---

## Pushing images to AWS ECR

There is no shared CI/CD pipeline. Each person builds and pushes images to **their own** AWS ECR using their own AWS credentials. Nothing is shared.

**Requirements:** AWS CLI v2, Docker, two ECR repositories created in your account.

| Repository | Image |
|---|---|
| your ECR frontend repo name | Nginx + static files |
| your ECR backend repo name | FastAPI application |

PostgreSQL uses `postgres:16-alpine` from Docker Hub — no ECR repo needed.

### Step 1 — Configure AWS CLI

```bash
aws configure        # single profile
# or
export AWS_PROFILE=<your-profile-name>   # if you have multiple profiles
```

### Step 2 — Fill in your .env

```bash
cp .env.example .env
```

Edit `.env` with your values (account ID, region, repo names). This file is git-ignored and never committed.

### Step 3 — Run the script

```bash
bash scripts/push-to-ecr.sh
```

Tag a specific release without editing `.env`:

```bash
IMAGE_TAG=v1.2.3 bash scripts/push-to-ecr.sh
```

---

## Kubernetes deployment

### On your desktop / any machine with full repo access

Label your nodes once:

```bash
kubectl label node worker1 worker2 worker3 worker4 topology.kubernetes.io/region=onsite
kubectl label node worker5 worker6 topology.kubernetes.io/region=cloud
```

### On the control plane — sparse clone (deploy/ folder only)

```bash
git clone --filter=blob:none --no-checkout <your-repo-url>
cd k8s-3tier-app
git sparse-checkout init --no-cone
git sparse-checkout set deploy
git checkout main
```

Then deploy everything in one command:

```bash
bash deploy/deploy.sh
```

The script applies all manifests in the correct dependency order and prints pod status at the end.

To pull updates and redeploy:

```bash
git pull
bash deploy/deploy.sh
```

---

## Monitoring

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install kube-prom-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values deploy/monitoring/values-kube-prometheus-stack.yaml
```

Grafana is available on NodePort **32000** — username `admin` / password `admin123`.
