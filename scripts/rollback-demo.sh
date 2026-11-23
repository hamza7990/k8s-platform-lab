#!/usr/bin/env bash
# Shows a bad release and the rollback, on whatever cluster kubectl points at.
# Needs the release "app" to be installed already, and the image
# k8s-platform-app:broken to exist in the cluster (docker build --build-arg BROKEN=1).
set -euo pipefail

RELEASE="${RELEASE:-app}"
CHART="${CHART:-helm/app}"
VALUES="${VALUES:-helm/app/values-dev.yaml}"
DEPLOY="$RELEASE-app"

step() { printf '\n== %s\n' "$*"; }

step "1. Release history before the bad upgrade"
helm history "$RELEASE"

step "2. Upgrade to image tag 'broken' (it starts, but /ready answers 503)"
# --wait makes helm wait for the pods to be ready. They never will be,
# so after the timeout helm reports a failed upgrade.
if helm upgrade "$RELEASE" "$CHART" -f "$VALUES" --set image.tag=broken \
  --wait --timeout 60s; then
  echo "the broken release was accepted, something is wrong with the demo"
  exit 1
fi
echo "upgrade failed as expected"

step "3. What the cluster looks like now"
kubectl get pods -l app.kubernetes.io/instance="$RELEASE"
echo
echo "The old pods are still serving: maxUnavailable is 0, so Kubernetes"
echo "kept them until the new pod became ready, which never happened."
kubectl rollout status "deploy/$DEPLOY" --timeout=5s || true
helm history "$RELEASE"

step "4. Traffic still works during the failed release"
curl -sf -H "Host: app.local" http://localhost/health
echo

step "5. helm rollback to the last good revision"
GOOD="$(helm history "$RELEASE" -o json \
  | jq -r '[.[] | select(.status == "deployed" or .status == "superseded")] | last | .revision')"
echo "last good revision: $GOOD"
helm rollback "$RELEASE" "$GOOD" --wait --timeout 120s

step "6. Healthy again"
kubectl rollout status "deploy/$DEPLOY" --timeout=120s
kubectl get pods -l app.kubernetes.io/instance="$RELEASE"
helm history "$RELEASE"
curl -sf -H "Host: app.local" http://localhost/ | jq .
VERSION="$(curl -sf -H "Host: app.local" http://localhost/ | jq -r .version)"
[ "$VERSION" != "broken" ] || { echo "still on the broken version"; exit 1; }
echo "rollback demo passed"
