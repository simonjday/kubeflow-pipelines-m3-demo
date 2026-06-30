#!/usr/bin/env bash
#
# scripts/cluster-stop.sh
#
# Stops the Docker containers backing the kind cluster nodes without
# deleting the cluster. This frees the CPU/RAM Docker Desktop/Colima was
# giving the cluster, while keeping all cluster state (etcd, PVs, installed
# manifests) on disk so `cluster-resume.sh` brings everything straight back.
#
# This is NOT the same as `kind delete cluster` — nothing is destroyed here.
#
# Usage:
#   ./scripts/cluster-stop.sh [cluster-name]
#   (default cluster-name: kubeflow-demo)
#
set -euo pipefail

CLUSTER_NAME="${1:-kubeflow-demo}"

echo "==> Looking for Docker containers belonging to kind cluster '$CLUSTER_NAME'"
CONTAINERS="$(docker ps -a --filter "label=io.x-k8s.kind.cluster=${CLUSTER_NAME}" --format '{{.Names}}')"

if [[ -z "$CONTAINERS" ]]; then
  echo "No containers found for cluster '$CLUSTER_NAME'."
  echo "Does it exist? Check with: kind get clusters"
  exit 1
fi

echo "Found:"
echo "$CONTAINERS" | sed 's/^/  - /'
echo

echo "==> Stopping containers"
docker stop $CONTAINERS

echo
echo "Cluster '$CLUSTER_NAME' is stopped. Docker Desktop/Colima CPU and memory"
echo "allocated to these containers is now released back to the host."
echo
echo "Resume with: ./scripts/cluster-resume.sh $CLUSTER_NAME"
