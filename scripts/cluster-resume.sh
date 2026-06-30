#!/usr/bin/env bash
#
# scripts/cluster-resume.sh
#
# Starts the Docker containers backing a previously stopped kind cluster
# (see cluster-stop.sh), waits for the API server and core pods to come
# back healthy, and reminds you how to re-open the port-forwards you'll
# want (KFP UI, ArgoCD UI).
#
# Usage:
#   ./scripts/cluster-resume.sh [cluster-name]
#   (default cluster-name: kubeflow-demo)
#
set -euo pipefail

CLUSTER_NAME="${1:-kubeflow-demo}"
KIND_CONTEXT="kind-${CLUSTER_NAME}"

echo "==> Looking for Docker containers belonging to kind cluster '$CLUSTER_NAME'"
CONTAINERS="$(docker ps -a --filter "label=io.x-k8s.kind.cluster=${CLUSTER_NAME}" --format '{{.Names}}')"

if [[ -z "$CONTAINERS" ]]; then
  echo "No containers found for cluster '$CLUSTER_NAME'."
  echo "Does it exist? Check with: kind get clusters"
  echo "If it was deleted (not just stopped), recreate it instead:"
  echo "  kind create cluster --name $CLUSTER_NAME --config kind/kind-cluster.yaml"
  exit 1
fi

echo "Found:"
echo "$CONTAINERS" | sed 's/^/  - /'
echo

echo "==> Starting containers"
docker start $CONTAINERS

echo "==> Switching kubectl context to $KIND_CONTEXT"
kubectl config use-context "$KIND_CONTEXT" >/dev/null

echo "==> Waiting for the API server to respond"
ATTEMPTS=0
until kubectl get --raw='/readyz' >/dev/null 2>&1; do
  ATTEMPTS=$((ATTEMPTS + 1))
  if [[ $ATTEMPTS -gt 60 ]]; then
    echo "API server did not become ready after 5 minutes. Check 'docker logs' on the"
    echo "control-plane container or fall back to recreating the cluster."
    exit 1
  fi
  sleep 5
done
echo "API server is ready."

echo "==> Waiting for core node(s) to report Ready"
kubectl wait --for=condition=Ready nodes --all --timeout=180s

echo "==> Waiting for pods in 'kubeflow' and 'argocd' namespaces to settle (best effort)"
kubectl wait --for=condition=Ready pods --all -n kubeflow --timeout=180s 2>/dev/null || \
  echo "    (kubeflow namespace not present or pods still starting — check manually)"
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=180s 2>/dev/null || \
  echo "    (argocd namespace not present or pods still starting — check manually)"

echo
echo "============================================================"
echo " Cluster '$CLUSTER_NAME' is back up."
echo
echo " Re-open port-forwards as needed:"
echo "   kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8090:80"
echo "   kubectl -n argocd port-forward svc/argocd-server 8080:443"
echo "============================================================"
