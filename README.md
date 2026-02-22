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
        ├── Prometheus  scrapes /api/health on backend
        └── Grafana     NodePort 32000
```

### Deployment topology

Each application tier has two separate Kubernetes Deployments that share one Service:

| Deployment | Replicas | Node affinity label |
|---|---|---|
| `frontend-onprem` | 2 | `topology.kubernetes.io/region=on-prem` |
| `frontend-cloud` | 1 | `topology.kubernetes.io/region=cloud` |
| `backend-onprem` | 2 | `topology.kubernetes.io/region=on-prem` |
| `backend-cloud` | 1 | `topology.kubernetes.io/region=cloud` |
| `postgres` (StatefulSet) | 1 | none |

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
    │   │   ├── deploy-onprem.yaml 2 replicas, on-prem affinity
    │   │   └── deploy-cloud.yaml  1 replica, cloud affinity
    │   ├── frontend/
    │   │   ├── service.yaml
    │   │   ├── deploy-onprem.yaml 2 replicas, on-prem affinity
    │   │   └── deploy-cloud.yaml  1 replica, cloud affinity
    │   └── ingress/
    │       └── ingress.yaml       nginx ingress class
    └── monitoring/
        └── values-kube-prometheus-stack.yaml
```

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

### Prerequisites

- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) installed and configured
- Docker running locally
- Two ECR repositories created in your AWS account

**Required ECR repositories:**

| Repository | Image |
|---|---|
| your ECR frontend repo name | Nginx + static files |
| your ECR backend repo name | FastAPI application |

PostgreSQL uses the public `postgres:16-alpine` image from Docker Hub — no ECR repo needed.

### Step 1 — Configure AWS CLI

```bash
aws configure
```

Enter your `AWS Access Key ID`, `Secret Access Key`, and default region. This stores credentials locally in `~/.aws/credentials` — never in this repo.

### Step 2 — Fill in your .env

```bash
cp .env.example .env
```

Then edit `.env`:

```dotenv
AWS_ACCOUNT_ID=123456789012
AWS_REGION=eu-west-1
ECR_FRONTEND_REPO=your-frontend-repo-name
ECR_BACKEND_REPO=your-backend-repo-name
IMAGE_TAG=latest
```

This file is git-ignored and never committed. Each person keeps their own copy with their own values.

### Step 3 — Run the script

```bash
bash scripts/push-to-ecr.sh
```

The script reads `.env` automatically, authenticates to your ECR using the AWS CLI credentials already on your machine, then builds and pushes both images.

You can also tag a specific release without editing `.env`:

```bash
IMAGE_TAG=v1.2.3 bash scripts/push-to-ecr.sh
```

---

## Kubernetes deployment

Label your nodes before applying manifests:

```bash
kubectl label node <node-name> topology.kubernetes.io/region=on-prem
kubectl label node <node-name> topology.kubernetes.io/region=cloud
```

Update the `image:` fields in the four deployment files to point to your ECR URIs:

```
deploy/base/backend/deploy-onprem.yaml
deploy/base/backend/deploy-cloud.yaml
deploy/base/frontend/deploy-onprem.yaml
deploy/base/frontend/deploy-cloud.yaml
```

Then apply:

```bash
kubectl apply -R -f deploy/base/
```

---

## Monitoring

Install the Prometheus + Grafana stack via Helm:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install kube-prom-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values deploy/monitoring/values-kube-prometheus-stack.yaml
```

Grafana is available on NodePort **32000** with username `admin` / password `admin123`.
