#!/usr/bin/env bash
#
# argocd/bootstrap.sh
#
# Installs ArgoCD into the kubeflow-demo kind cluster, waits for it to
# become ready, prints the initial admin password, and (optionally)
# registers the kubeflow-pipelines Application so ArgoCD takes over
# managing the KFP overlay instead of you running `kubectl apply -k` by hand.
#
# Usage:
#   ./argocd/bootstrap.sh                 # install ArgoCD only
#   ./argocd/bootstrap.sh --with-app      # also apply gitops/argocd-application.yaml
#
set -euo pipefail

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"
KIND_CONTEXT="${KIND_CONTEXT:-kind-kubeflow-demo}"
WITH_APP=false

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for arg in "$@"; do
  case "$arg" in
    --with-app) WITH_APP=true ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

echo "==> Checking kubectl context"
current_context="$(kubectl config current-context || true)"
if [[ "$current_context" != "$KIND_CONTEXT" ]]; then
  echo "    Current context is '$current_context', expected '$KIND_CONTEXT'."
  echo "    Switching context..."
  kubectl config use-context "$KIND_CONTEXT"
fi

echo "==> Creating namespace '$ARGOCD_NAMESPACE' (if not present)"
kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing ArgoCD ($ARGOCD_VERSION manifest) into '$ARGOCD_NAMESPACE'"
# --server-side is required here: client-side `kubectl apply` stores the full
# manifest in a kubectl.kubernetes.io/last-applied-configuration annotation,
# and the applicationsets.argoproj.io CRD is large enough to blow past
# Kubernetes' 262144-byte annotation limit ("Too long: may not be more than
# 262144 bytes"). Server-side apply doesn't use that annotation at all.
kubectl apply -n "$ARGOCD_NAMESPACE" --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> Waiting for ArgoCD deployments to become available (this can take a few minutes on first pull)"
kubectl -n "$ARGOCD_NAMESPACE" wait --for=condition=available --timeout=300s deployment --all

echo "==> Patching argocd-server to NodePort for local access (kind has no cloud LB)"
kubectl -n "$ARGOCD_NAMESPACE" patch svc argocd-server -p '{"spec": {"type": "NodePort", "ports": [{"port": 443, "targetPort": 8080, "nodePort": 30443, "name": "https"}]}}'

echo "==> Fetching initial admin password"
# ArgoCD >= 2.x stores the bootstrap password in a secret deleted after first
# login/password change. If it's already been rotated, this will print nothing.
ADMIN_PW="$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"

echo
echo "============================================================"
echo " ArgoCD is installed in namespace: $ARGOCD_NAMESPACE"
echo
echo " UI / API access (NodePort, kind extraPortMappings required —"
echo " see kind/kind-cluster.yaml, or use port-forward instead):"
echo "   kubectl -n $ARGOCD_NAMESPACE port-forward svc/argocd-server 8080:443"
echo "   https://localhost:8080"
echo
echo " Username: admin"
if [[ -n "$ADMIN_PW" ]]; then
  echo " Password: $ADMIN_PW"
else
  echo " Password: (already rotated or not yet created — check"
  echo "   kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret)"
fi
echo
echo " CLI login (optional, requires argocd CLI: brew install argocd):"
echo "   argocd login localhost:8080 --username admin --password '<password>' --insecure"
echo "============================================================"
echo

if [[ "$WITH_APP" == true ]]; then
  echo "==> Applying gitops/argocd-application.yaml"
  echo "    NOTE: edit repoURL in that file to point at your pushed repo first."
  kubectl apply -f "$REPO_ROOT/gitops/argocd-application.yaml"
  echo "==> Application 'kubeflow-pipelines' registered. Check sync status with:"
  echo "    kubectl -n $ARGOCD_NAMESPACE get application kubeflow-pipelines"
fi

echo "Done."
