#!/usr/bin/env bash
set -euo pipefail

# StepUp one-shot spin-up on Docker Desktop + kind, deployed via Radius.
#   kind -> Drasi+Dapr -> Dapr(app) -> Radius -> recipes -> build/load images ->
#   namespaces + webhook secret -> rad deploy (Postgres + Redis recipe + 4 services
#   + Dapr components) -> sidecar restart -> Drasi source/queries/reactions.
# Prereqs: Docker Desktop running; kind, kubectl, rad, drasi, dapr, docker on PATH.
# Idempotent. For a clean slate: kind delete cluster --name stepup.
# Run from anywhere; paths resolve to the repo root.

CLUSTER=stepup
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# kind must use the Docker provider — clear any stale podman override, or
# `kind load` hits "no nodes found".
unset KIND_EXPERIMENTAL_PROVIDER

# --- 0. Preflight -----------------------------------------------------------
docker info >/dev/null 2>&1 || { echo "Docker Desktop isn't running." >&2; exit 1; }
for t in kind kubectl rad drasi dapr docker; do
  command -v "$t" >/dev/null 2>&1 || { echo "Missing tool: $t" >&2; exit 1; }
done

# --- 1. kind cluster --------------------------------------------------------
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "kind cluster '$CLUSTER' exists."
else
  echo "Creating kind cluster '$CLUSTER'..."
  kind create cluster --name "$CLUSTER"
fi
kubectl config use-context "kind-$CLUSTER" >/dev/null

# Point the drasi CLI at THIS cluster. It caches its last target in ~/.drasi, so
# after any AKS run `drasi` commands would otherwise hit the cloud cluster
# ("dial tcp ... stepup-aks-...: no such host").
drasi env kube

# --- 2. Drasi + Dapr control plane (drasi init installs both) ---------------
if kubectl get namespace drasi-system >/dev/null 2>&1; then
  echo "Drasi already installed."
else
  echo "Installing Drasi + Dapr (a few minutes)..."
  drasi init
fi

# --- 2b. Ensure a Dapr control plane for the app. drasi init doesn't reliably
#         leave the components.dapr.io CRD + injector the app's Dapr components
#         need. Pin 1.14 to match Drasi/AKS and avoid Dapr 1.18's fatal-on-
#         component behaviour, which crash-loops the notifier on a secret race.
if ! kubectl get crd components.dapr.io >/dev/null 2>&1; then
  echo "Installing Dapr control plane (1.14)..."
  dapr init -k --runtime-version 1.14.4 --wait
fi

# --- 3. Radius control plane + environment ----------------------------------
if kubectl get namespace radius-system >/dev/null 2>&1; then
  echo "Radius already installed."
else
  echo "Installing Radius..."
  rad install kubernetes
fi

echo "Configuring Radius environment + recipes..."
bash scripts/radius-recipes.sh

# --- 4. Build + side-load the four service images ---------------------------
echo "Building and loading images..."
for svc in Simulator Clock Notifier Dashboard; do
  img="stepup/$(echo "$svc" | tr '[:upper:]' '[:lower:]'):local"
  docker build -t "$img" "src/$svc"
  kind load docker-image "$img" --name "$CLUSTER"
done

# --- 5. Namespaces + webhook secret BEFORE rad deploy -----------------------
#        The notifier's `discord` binding resolves its secretKeyRef at startup, so
#        the secret must exist before deploy. The drasi-system pubsub component
#        (the recipe-Redis broker the Drasi reaction shares) needs its namespace.
#        All idempotent.
WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-$(sed -n 's/.*"discordWebhookUrl"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' src/Notifier/secrets.json 2>/dev/null)}"
[ -n "$WEBHOOK_URL" ] || { echo "Set DISCORD_WEBHOOK_URL or provide src/Notifier/secrets.json." >&2; exit 1; }
kubectl create namespace drasi-system   --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace default-stepup --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic notifier-webhook -n default-stepup \
  --from-literal=url="$WEBHOOK_URL" --dry-run=client -o yaml | kubectl apply -f -

# --- 6. Deploy the app via Radius -------------------------------------------
#        Tolerate a first-pass notifier failure (Dapr secret-timing race); the
#        rollout restart clears it and the rollout status then asserts real health.
echo "Deploying StepUp via Radius..."
rad deploy infra/app.bicep --group default --environment default \
  || echo "  (first deploy reported a failure — recovering the Dapr services below)"
kubectl wait --for=condition=ready pod -l app=postgres -n default --timeout=180s

echo "Restarting Dapr services so sidecars load their components..."
for d in simulator clock notifier; do kubectl rollout restart "deploy/$d" -n default-stepup; done
for d in simulator clock notifier; do kubectl rollout status  "deploy/$d" -n default-stepup --timeout=180s; done

# --- 7. Drasi: source -> queries -> reactions -------------------------------
echo "Applying Drasi source..."
drasi apply -f drasi/source.yaml
drasi wait  -f drasi/source.yaml -t 180

echo "Applying Drasi queries..."
for q in behind-pace collective-progress daily-smashed new-leader race-to-goal; do
  drasi apply -f "drasi/$q.yaml"
done

echo "Applying Drasi reactions..."
for r in debug notifier-reaction dashboard-reaction; do
  drasi apply -f "drasi/$r.yaml"
done

cat <<DONE

StepUp is up on the '$CLUSTER' cluster (deployed via Radius).

  Pods:       kubectl get pods -n default-stepup
  Dashboard:  kubectl port-forward -n default-stepup deploy/dashboard 9090:80
              then open http://localhost:9090
  Reactions take ~1 min to go Available: drasi list reaction
  Tear down:  kind delete cluster --name $CLUSTER
DONE