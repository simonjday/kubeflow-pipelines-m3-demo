# kubeflow-pipelines-m3-demo

Standalone Kubeflow Pipelines (KFP) deployment on a local `kind` cluster, built and tested on Apple Silicon (M3). Deploys KFP 2.16.1 via Kustomize, with an Argo-Workflows backend, cert-manager-issued TLS for the cache server, and a sample 3-step pipeline (preprocess → train → evaluate).

Includes the same overlay pattern wrapped as an ArgoCD `Application` for teams running GitOps (ArgoCD + Gitea/GitHub) instead of `kubectl apply -k .` by hand.

## Repo layout

```
.
├── kind/
│   └── kind-cluster.yaml          # local kind cluster config
├── argocd/
│   └── bootstrap.sh               # installs ArgoCD into the kind cluster
├── platform-tools/
│   └── kubeflow-pipeline/
│       └── kustomization.yaml     # KFP Kustomize overlay (NodePort UI, SeaweedFS fsGroup fix, cache-deployer removed)
├── pipelines/
│   ├── requirements.txt
│   ├── pipeline.py                # KFP SDK pipeline definition + run trigger
│   └── components/
│       ├── preprocess.py
│       ├── train.py
│       └── evaluate.py
├── gitops/
│   └── argocd-application.yaml    # ArgoCD Application wrapping the same overlay
├── scripts/
│   ├── cluster-stop.sh            # stop kind containers to free CPU/RAM
│   └── cluster-resume.sh          # bring the stopped cluster back up
└── docs/
    └── kubeflow-technical-overview.md
```

## Prerequisites

- Docker Desktop or Colima (6 vCPU / 10 GB RAM minimum allocated)
- `kind`, `kubectl`, `kustomize` (`brew install kind kubectl kustomize`)
- Python 3.11+

## Quickstart

```bash
# 1. Create the kind cluster
kind create cluster --name kubeflow-demo --config kind/kind-cluster.yaml

# 2. Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.20.0/cert-manager.yaml
kubectl wait --for=condition=available --timeout=120s -n cert-manager deployment --all

# 3. Install KFP cluster-scoped resources
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=2.16.1"

# 4. Deploy KFP
kubectl apply -k platform-tools/kubeflow-pipeline
kubectl get pods -n kubeflow -w

# 5. Access the UI
kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8090:80
# http://localhost:8090/#/pipelines

# 6. Trigger the sample pipeline
python3 -m venv .venv && source .venv/bin/activate
pip install -r pipelines/requirements.txt
python pipelines/pipeline.py
```

## GitOps path (ArgoCD, recommended over step 4 above)

> **Prerequisite:** cert-manager (step 2 of Quickstart above) must already be installed in the cluster before ArgoCD syncs this overlay — the overlay now includes a cert-manager `Issuer`/`Certificate` (see `platform-tools/kubeflow-pipeline/kustomization.yaml`) that issues the cache-server's TLS secret, and `kustomize build` will fail on those CRD kinds if cert-manager isn't present yet. If you're doing the GitOps path from a fresh cluster, install cert-manager manually first (step 2), *then* bootstrap ArgoCD.

Rather than running `kubectl apply -k platform-tools/kubeflow-pipeline` by hand every time, bootstrap ArgoCD into the same kind cluster and let it manage the KFP overlay declaratively.

### 1. Install ArgoCD into the cluster

```bash
./argocd/bootstrap.sh
```

This installs the upstream ArgoCD manifests into the `argocd` namespace, waits for all deployments to become available, patches `argocd-server` to a NodePort (kind has no cloud load balancer), and prints the initial admin password.

Log in via port-forward:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
# https://localhost:8080  (user: admin, password printed by bootstrap.sh)
```

### 2. Point the Application at your repo

Edit `gitops/argocd-application.yaml` and replace the placeholder `repoURL` with wherever you've pushed this repo (GitHub or your Gitea instance).

### 3. Register the Application

Either re-run the bootstrap with the flag:

```bash
./argocd/bootstrap.sh --with-app
```

or apply it directly if ArgoCD is already running:

```bash
kubectl apply -f gitops/argocd-application.yaml
```

ArgoCD will then sync `platform-tools/kubeflow-pipeline` into the `kubeflow` namespace and keep it in sync (auto-prune + self-heal are enabled in the Application spec). From here, changes to the Kustomize overlay are made via git commits, not `kubectl apply`.

```bash
kubectl -n argocd get application kubeflow-pipelines
```

## Pause / resume the cluster (save resources when idle)

A kind cluster running KFP + ArgoCD holds onto a meaningful chunk of CPU/RAM on Docker Desktop/Colima even when you're not actively using it. Rather than deleting and recreating the cluster between sessions, stop and start the underlying Docker containers — cluster state (etcd, PVs, all installed manifests) is preserved on disk either way.

```bash
# Before closing your laptop / freeing up resources for other lab work
./scripts/cluster-stop.sh

# Next time you want to pick back up
./scripts/cluster-resume.sh
```

`cluster-resume.sh` waits for the API server and core pods to report healthy, then reminds you which port-forwards to re-open. This is not the same as `kind delete cluster` — nothing is destroyed, so KFP runs, pipeline history, and ArgoCD's sync state all survive a stop/resume cycle.

## Teardown

```bash
kind delete cluster --name kubeflow-demo
```

## Known issue: Apple Silicon (ARM64)

Core KFP pods (`ml-pipeline`, `workflow-controller`, `seaweedfs`, `mysql:8.0.26`) are multi-arch and install cleanly on kind on M-series Macs. If you extend this to the full Kubeflow reference platform or Kubeflow Hub (Model Registry), expect `ImagePullBackOff` on some `kubeflownotebookswg` and dependency images — this is a known, tracked gap (see Kubeflow's GSoC 2026 ARM support project).

## References

- https://www.kubeflow.org/docs/components/pipelines/operator-guides/installation/
- https://devopscube.com/setup-kubeflow-pipelines-kubernetes/
- https://github.com/kubeflow/pipelines

## License

MIT — see `LICENSE`.
