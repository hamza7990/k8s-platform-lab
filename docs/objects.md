# The objects in the chart, in plain words

All templates are in `helm/app/templates/`. Helm fills them with values from
`values.yaml` (and `values-dev.yaml` or `values-prod.yaml` on top).

**Deployment** (`deployment.yaml`). Says "keep N copies of this container
running". If a pod dies it starts another. Important parts:
- `strategy: RollingUpdate` with `maxSurge: 1` and `maxUnavailable: 0`: during
  an update start one new pod first, remove an old one only after the new one
  is ready.
- `resources`: `requests` is what the scheduler reserves for the pod (and what
  the HPA percentage is based on), `limits` is the ceiling.
- `livenessProbe` on `/health`: if it fails, the container is restarted.
- `readinessProbe` on `/ready`: if it fails, the pod stays out of the Service.
  This is the check that stops a bad release.
- `securityContext`: not root, no privilege escalation, read-only filesystem,
  all Linux capabilities dropped.
- `checksum/config` annotation: when the ConfigMap changes, the hash changes
  and the pods are replaced, so they pick up the new settings.

**Service** (`service.yaml`). A stable name and IP inside the cluster that
sends traffic to every ready pod with the matching labels. Pods come and go,
the Service stays.

**Ingress** (`ingress.yaml`). A rule for traffic from outside: requests for
host `app.local` go to the Service. The ingress-nginx controller reads these
rules and does the routing.

**HorizontalPodAutoscaler** (`hpa.yaml`). Adds pods when average CPU is above
the target (70 percent of the request) and removes them when it falls, between
`minReplicas` and `maxReplicas`. It reads the numbers from metrics-server.

**ConfigMap** (`configmap.yaml`). Plain settings (`APP_ENV`, `GREETING`),
passed to the container as environment variables.

**Secret reference** (in `deployment.yaml`). The container reads `API_KEY`
from a Secret called `app-secret`. The chart does not contain the value; the
Secret is created outside the chart.

**PodDisruptionBudget** (`pdb.yaml`). Limits voluntary disruptions, like a node
drain: at least `minAvailable` pods must stay up.

**ServiceMonitor** (`servicemonitor.yaml`). Tells the Prometheus Operator to
scrape `/metrics`. Only created when `serviceMonitor.enabled` is true.

**Prometheus** (`k8s/monitoring/prometheus.yaml`). Not part of the chart. A
Deployment, Service, ConfigMap with the scrape config, and a ServiceAccount
with read access to pods so it can discover them.
