# k8s-platform-lab

[![CI](https://github.com/hamza7990/k8s-platform-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/hamza7990/k8s-platform-lab/actions/workflows/ci.yml)

A tiny HTTP service packaged as a Helm chart and deployed for real on a
`kind` (Kubernetes in Docker) cluster inside GitHub Actions. CI installs an
ingress controller and metrics-server, deploys the chart, calls the app through
the ingress, shows the autoscaler, checks that Prometheus scrapes the pods, and
finally breaks a release on purpose and rolls it back.

## Architecture

```
 curl -H "Host: app.local" http://localhost/
        |
        v  (kind maps port 80 to the node)
 +------------------+
 | ingress-nginx    |  Ingress: app.local -> Service
 +--------+---------+
          v
 +------------------+     +-------------------------------------+
 | Service (ClusterIP)|--->| Deployment: 2-4 pods                |
 +------------------+     |  FastAPI /health /ready /metrics /  |
                          |  env from ConfigMap + Secret        |
   HPA (CPU 70%) --scales-> readiness + liveness probes          |
   PDB (minAvailable 1)   |  non-root, read-only filesystem     |
                          +------------------+------------------+
                                             ^ scrape /metrics
                          +------------------+------------------+
                          | Prometheus (namespace monitoring)   |
                          +-------------------------------------+
   metrics-server feeds CPU numbers to the HPA and `kubectl top`
```

## Repository map

| Path | What it is |
| --- | --- |
| `app/main.py` | FastAPI service: `/`, `/health`, `/ready`, `/metrics` |
| `tests/` | pytest tests for the endpoints |
| `Dockerfile` | slim Python image, non-root user, `BROKEN` build arg for the demo |
| `helm/app/` | the chart: templates, `values.yaml`, `values-dev.yaml`, `values-prod.yaml` |
| `kind/cluster.yaml` | cluster config that exposes port 80 for the ingress |
| `k8s/monitoring/prometheus.yaml` | minimal Prometheus with RBAC and a scrape config |
| `scripts/rollback-demo.sh` | bad release, failed rollout, `helm rollback`, healthy again |
| `docs/objects.md` | every Kubernetes object in plain words |
| `.github/workflows/ci.yml` | the pipeline below |

## Run it yourself

Needs Docker, `kind`, `kubectl` and `helm`.

```
docker build -t k8s-platform-app:1.0.0 .
docker build --build-arg BROKEN=1 -t k8s-platform-app:broken .
kind create cluster --name lab --config kind/cluster.yaml
kind load docker-image k8s-platform-app:1.0.0 k8s-platform-app:broken --name lab

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/kind/deploy.yaml
kubectl create secret generic app-secret --from-literal=API_KEY=change-me
helm upgrade --install app helm/app -f helm/app/values-dev.yaml --wait

curl -H "Host: app.local" http://localhost/
bash scripts/rollback-demo.sh
kind delete cluster --name lab
```

## What the pipeline does

`ci.yml` has three jobs:

1. `app`: ruff, pytest, ShellCheck on `scripts/`.
2. `chart`: `helm lint` (default, dev and prod values), then
   `helm template | kubeconform -strict` for dev and prod values and for the
   Prometheus manifest.
3. `kind` (after the first two): builds two images (`1.0.0` and `broken`),
   creates the cluster, loads the images, installs ingress-nginx and
   metrics-server, creates the Secret, runs `helm upgrade --install --wait`,
   then
   - calls `/health`, `/`, `/ready`, `/metrics` through the ingress,
   - prints the HPA status once metrics-server reports CPU,
   - installs Prometheus and queries `up{job="app"}`, which must show both pods,
   - runs `scripts/rollback-demo.sh`.

The rollback demo prints each step:

1. `helm upgrade --set image.tag=broken --wait`: the new pod starts but
   `/ready` returns 503, so it never becomes ready and helm fails after 60 s.
2. The old pods keep serving, because `maxUnavailable: 0` means Kubernetes
   removes an old pod only after its replacement is ready. A curl proves it.
3. `helm rollback` to the last good revision, wait for the rollout, check
   `/` reports the good version.

## Notes

- The chart does not create the Secret. It only references it by name, which
  is how it works in real clusters (sealed secrets, external secrets, or a
  manual `kubectl create`). CI creates one with a random value.
- `ServiceMonitor` needs the Prometheus Operator, so it is only rendered with
  prod values and is checked by kubeconform, not installed. The CI Prometheus
  is a plain manifest that finds pods through the Kubernetes API.
- The images are not pushed anywhere. `kind load` copies them into the node.

## What I would add next

- Push the image to GHCR with the commit SHA as the tag, and deploy that tag.
- Argo CD or Flux so the cluster pulls changes from git.
- NetworkPolicies, and TLS on the ingress with cert-manager.
- A load test step so the HPA really scales up.
- Grafana with a dashboard stored in the repo, and alert rules.
