# Kubeflow: Technical Overview, Architecture, Comparison & M3 Mac Demo

*Prepared for a Kubernetes/GitOps platform engineering audience. June 2026.*

---

## 1. TL;DR

Kubeflow is the CNCF-adjacent, Kubernetes-native AI/ML platform originally spun out of Google in 2017 to run TensorFlow jobs on Kubernetes ("Kube" + "Flow"). With the 1.11 release (Dec 2025) it was repositioned from "MLOps toolkit" to the **Kubeflow AI Reference Platform**, shifting emphasis toward GenAI, distributed LLM training/fine-tuning, and leaner per-namespace overhead. It now ships as **nine independently installable subprojects** rather than one monolith, and 1.11 dropped MinIO for SeaweedFS as the default object store.

For your stack — kind-based labs, ArgoCD GitOps, Kyverno policy, CFK Kafka, OpenShift enterprise contexts — the relevant fit is: **Kubeflow Pipelines (KFP) + Kubeflow Trainer as Argo-Workflows-backed, Kustomize/Helm-deployable CRDs that slot straight into your existing GitOps pattern.** The full "central dashboard + Istio + Dex" platform is a heavier, more opinionated install and is the part most likely to fight you on Apple Silicon and in OpenShift SCC-restricted environments.

---

## 2. What Kubeflow actually is

Kubeflow is an open-source platform that layers ML/AI-specific Custom Resource Definitions (CRDs) and controllers on top of vanilla Kubernetes, so that "ML pipeline," "training job," "hyperparameter trial," and "model registry entry" become first-class API objects instead of bespoke scripts.

Key facts, all from kubeflow.org:

- Originated at Google in 2017, open-sourced under Apache 2.0, with early contributions from Amazon, Intel, Bloomberg, and Apple.
- The platform models the AI lifecycle as a sequence: **Data Preparation → Model Development → Model Training → Model Optimization → Model Serving**, with the Model Registry sitting alongside as the system of record for artifacts and metadata across that loop.
- As of 1.11, Kubeflow ships **component-based Helm charts**, so you install only the subprojects you need (e.g., just Pipelines + Trainer) instead of the full reference platform — a meaningful change from the older "all-or-nothing" manifests model.
- Per-namespace/profile overhead now defaults to zero for idle namespaces, and the default object store moved from MinIO to SeaweedFS.

## 3. Architecture: the nine subprojects

Per the official subproject index, Kubeflow today is composed of:

| Subproject | What it does |
|---|---|
| **Kubeflow SDK** | Unified Python SDK surface across subprojects |
| **Kubeflow Spark Operator** | Runs Spark jobs natively on Kubernetes for large-scale feature engineering/data prep |
| **Kubeflow Notebooks** | Managed JupyterLab / RStudio / VS Code environments running as pods in-cluster, shareable across a team |
| **Kubeflow Trainer** | Distributed training operator (PyTorch, JAX, DeepSpeed, XGBoost, Megatron, MLX, TorchTune built-in trainer); successor to the legacy v1 Training Operator (TFJob/PyTorchJob/etc.) |
| **Kubeflow Katib** | Hyperparameter tuning, neural architecture search (NAS), early stopping |
| **Kubeflow Hub** (formerly Model Registry) | Tracks model versions, lineage, approval status, and serving configuration through Create → Verify → Package → Release → Deploy → Monitor stages |
| **Kubeflow Pipelines (KFP)** | DAG-based ML workflow orchestration — the component most teams adopt first and the focus of Section 4 |
| **Kubeflow Dashboard** | Central web UI, profile/namespace management, multi-tenant auth surface |
| **Kubeflow Kale** | Notebook-to-pipeline conversion tooling |

Adjacent **ecosystem** projects that Kubeflow docs explicitly integrate with but don't own outright: **Feast** (feature store), **Elyra** (pipeline visual editor for JupyterLab), and **KServe** (model serving — Knative- or raw-Kubernetes-backed inference with autoscaling, canary rollout, and multi-model serving).

The full reference platform additionally wires in **Istio** (service mesh / traffic management) and **Dex + an OIDC client** (auth) at the control-plane layer — this is the part that adds the most operational weight and is where Charmed Kubeflow (Canonical's packaged distribution) differentiates with COS (Prometheus/Grafana/Loki) integration out of the box.

## 4. Kubeflow Pipelines deep dive

This is the subproject you'll touch first and most often, so it's worth understanding the internals (architecture detail per the DevOpsCube MLOps newsletter, June 2026 edition, and consistent with kubeflow.org/docs/components/pipelines).

### 4.1 What it is

KFP is a **standalone DAG runtime** — you can install it without the rest of Kubeflow. You author pipelines in Python using the `kfp` SDK with the `@dsl.pipeline` / `@dsl.component` decorators; you never write the DAG explicitly — Kubeflow infers task dependencies from data flow between component inputs/outputs.

Important architectural fact: **KFP uses Argo Workflows as its execution engine.** Argo is a Kubernetes-native DAG orchestrator that runs each task as a pod from a declarative YAML CRD. Kubeflow's value-add on top of Argo is the ML-aware layer: datasets, model artifacts, experiment tracking, metrics, lineage, and task-level caching — concepts Argo itself knows nothing about.

### 4.2 Core components (what gets deployed)

| Component | Role |
|---|---|
| `ml-pipeline` | API server — entry point for all SDK/CLI/UI calls |
| `ml-pipeline-ui` | Web UI |
| `workflow-controller` | The Argo Workflows controller — reconciles Workflow CRDs into pods |
| `mysql` | Stores pipeline definitions, experiments, run history, metadata |
| `seaweedfs-server` | S3-compatible object storage for artifacts (replaced MinIO as the default in 1.11) |
| `cache-server` / `cache-deployer` | Task-level result caching; deployer issues TLS certs for the cache webhook |
| ML Metadata (MLMD) pods (`metadata-envoy`, `metadata-grpc`, `metadata-writer`) | Track every task's inputs, outputs, parameters, and lineage |

Per-run, ephemeral pods are created dynamically: `system-dag-driver` (sets up the run's MLMD execution context), `system-container-driver` (checks cache, builds `executor_input` JSON), and `system-container-impl` (actually runs your component code).

### 4.3 Execution flow

1. The KFP SDK compiles your Python pipeline definition into an **Intermediate Representation (IR) YAML**.
2. The IR YAML is submitted to the `ml-pipeline` API server, which records the run in MySQL and creates an **Argo Workflow CRD**.
3. The Argo workflow controller reconciles that CRD and schedules pods.
4. For each task: a dag-driver pod initializes context in MLMD → a container-driver pod checks the cache (skip on hit) → a container-impl pod runs your actual code → results, metrics, and lineage land in MLMD.
5. **Task-level caching** means a failed pipeline can be re-run and only re-execute the steps downstream of the failure — meaningfully cheaper iteration than re-running a whole DAG.

### 4.4 Triggering pipelines in production

Three real patterns beyond manual SDK triggering: **scheduled/recurring runs** (cron or interval, native to KFP), **event-driven** (e.g., new data lands in object storage), and **CI/CD-triggered** (a pipeline run kicked off via the KFP API after a merge to main — this is the one that fits your ArgoCD/Gitea pattern most naturally).

### 4.5 Kubeflow Pipelines vs. Airflow

A question every DevOps engineer touching this asks. Short version: **Airflow is general-purpose workflow orchestration** (ETL, scheduled jobs); **KFP is purpose-built for ML** and understands datasets, model artifacts, metrics, and caching natively rather than requiring you to bolt that on.

---

## 5. Pros and cons

### Pros

- **Kubernetes-native end to end.** No separate orchestration substrate to operate — if you already run kind/EKS/OpenShift with GitOps, Kubeflow's CRDs slot into the same control plane, RBAC, and observability stack you already have.
- **Component-based installs (1.11+).** You're no longer forced into the full platform; install just KFP + Trainer via Helm and skip Istio/Dex if you don't need multi-tenant web auth.
- **Strong lineage and reproducibility.** MLMD-backed artifact/metric tracking plus task-level caching is a genuine production feature, not a tracking afterthought bolted on.
- **Cloud-portable.** Runs identically on GKE, EKS, AKS, OpenShift, or bare kind — no managed-service lock-in, which matters for your Barclays-pattern/UAE-sovereign enterprise contexts.
- **Backed by a real multi-vendor community** (Google origin, Amazon/Intel/Bloomberg/Apple early contributors, Canonical's Charmed distribution, Red Hat and Arrikto enterprise support) — not a single-vendor open-core project.
- **Broad framework support** for distributed training via Kubeflow Trainer: PyTorch, JAX, DeepSpeed, XGBoost, Megatron, MLX, plus a TorchTune built-in trainer for LLM fine-tuning.

### Cons

- **Real Kubernetes/Istio expertise required.** This is explicitly not a beginner-friendly product; full-platform deployments require comfort with Istio traffic management and multi-component CRD debugging.
- **Resource-intensive minimum footprint** for a full install — fine for your kind-devops-lab as a learning exercise, painful as a "just try it" evaluation on a laptop.
- **ARM64/Apple Silicon is still a second-class citizen.** Several `kubeflownotebookswg` images and dependency images (e.g., certain MySQL tags used by Model Registry) lack arm64 manifests, producing `ErrImagePull`/`ImagePullBackOff` on M-series Macs. Kubeflow's own GSoC 2026 project list includes an explicit initiative to fix this gap.
- **Upgrade path friction.** Major version bumps can involve breaking CRD changes; this is a real operational tax versus a managed SaaS platform.
- **Debugging is Kubernetes-shaped.** A failed pipeline step means reading pod logs, not a friendly stack trace in a web console — appropriate for you, less so for a data-science-only team.
- **Mindshare has fragmented since 2020–2021.** Distributed training increasingly defaults to Ray/KubeRay; MLflow has effectively won as the open-source model registry/tracking layer (most teams wire MLflow into KFP rather than using KFP's native experiment UI); KServe remains the serving default but competes with vLLM/TGI for LLM-specific serving.

---

## 6. Competitor comparison

| Platform | Model | Best fit | Where it beats Kubeflow | Where Kubeflow wins |
|---|---|---|---|---|
| **MLflow** | OSS library (Apache 2.0), self-hosted or managed via Databricks/SageMaker | Lightweight experiment tracking + model registry, framework-agnostic | No Kubernetes dependency, far lower operational overhead, best-in-class model registry UX | KFP gives you actual *orchestration* (DAGs, distributed training, scheduling) — MLflow has none of that natively |
| **AWS SageMaker** | Fully managed | AWS-native shops wanting minimal ops | Zero infra to run, deep AWS integration, serverless experiment tracking | No AWS lock-in; runs on any CNCF-conformant cluster, including on-prem/sovereign cloud (relevant for your Core42/UAE/Barclays-pattern enterprise work) |
| **Google Vertex AI** | Fully managed | GCP-native shops, BigQuery/Dataflow integration | Managed Pipelines (built on the same underlying tech as KFP, incidentally), zero cluster ops | Same portability argument — Vertex AI *is* effectively "Kubeflow Pipelines as a GCP managed service" |
| **Azure ML** | Fully managed | Microsoft-ecosystem shops | Automated ML pipelines, fairness/governance tooling, AKS-light operationally | Multi-cloud portability, no Azure dependency |
| **Flyte** | OSS, Kubernetes-native, strongly-typed Python DAGs | Greenfield 2026 ML pipeline projects, teams wanting stronger type safety than KFP | Increasingly viewed as the "default pick for greenfield" over KFP v1; cleaner typed-data contracts between tasks | KFP v2 is the credible counter for teams already standardized on Kubeflow; broader subproject ecosystem (Trainer, Katib, Hub) beyond just pipelines |
| **Metaflow** | OSS, originated at Netflix | AWS-centric teams wanting simple Python-first orchestration without deep Kubernetes knowledge | Much gentler learning curve for data scientists without K8s background | Multi-cloud/on-prem portability — Metaflow is effectively AWS-only in practice |
| **ZenML** | OSS core + managed SaaS ($99/mo tier) | Teams wanting an easy on-ramp with pluggable backends (can target Kubeflow itself as an orchestrator) | Far easier onboarding; managed option removes ops entirely | Kubeflow has the longer track record, larger community, and native multi-cloud/on-prem story |
| **Databricks (+ MLflow)** | Managed lakehouse platform | Teams whose data already lives in Databricks | Single platform for data + ML, managed MLflow bundled in | No lakehouse lock-in; pure Kubernetes-native fits your existing GitOps/Kyverno/ArgoCD stack instead of adopting a new platform paradigm |
| **Argo Workflows (bare)** | OSS, Kubernetes-native | Teams wanting raw DAG orchestration without an ML-specific layer | Lighter weight, you already understand it if you know KFP's internals | KFP is *built on* Argo and adds the ML-specific layer (artifacts, lineage, caching, experiment tracking) you'd otherwise hand-roll |

**2026 market read** (synthesized from multiple MLOps tooling surveys this year): No single platform wins outright. The pragmatic 2026 default for a self-hosted, Kubernetes-native, multi-cloud/on-prem shop — which describes your environment — is **Kubeflow Pipelines + Kubeflow Trainer for orchestration, with MLflow wired in for experiment tracking/registry** (since KFP's own metadata UI has lost mindshare to MLflow), and **KServe** for serving. That combination is exactly the open-source stack Cloudflare describes running for their internal GitOps-based MLOps platform (Kubeflow, deployKF, Airflow, MLflow).

---

## 7. Decision framework for your environment

Given your stack (kind-devops-lab, ArgoCD + Gitea GitOps, Kyverno policy-as-code, CFK Kafka, OpenShift in enterprise contexts):

- **Adopt Kubeflow Pipelines + Trainer, skip the full reference platform**, unless you specifically need the multi-tenant central dashboard with Istio/Dex auth for multiple data-science teams sharing one cluster. The component-based Helm charts in 1.11 make this trivial to scope down.
- **GitOps fit is strong**: KFP installs via Kustomize or Helm, both ArgoCD-native. Treat the `kustomization.yaml` patch file (NodePort exposure, cache-deployer removal, network policy tweaks) as just another ArgoCD `Application` source the way you'd manage any other platform component.
- **Don't use `kubectl apply` directly for anything beyond local kind experimentation** — wrap the same Kustomize manifests in an ArgoCD Application pointed at Gitea, consistent with how you already manage Kyverno and Kargo.
- **For OpenShift/restricted-SCC contexts**, expect to patch SecurityContexts (the SeaweedFS non-root `fsGroup`/`runAsUser` issue below is a preview of the kind of patching OpenShift will also demand) and budget extra time versus a vanilla EKS/kind install.
- **Wire MLflow alongside KFP from day one** rather than relying on KFP's native experiment tracking UI — this matches where the broader ecosystem has converged in 2026.

---

## 8. End-to-end demo: Kubeflow Pipelines on a local M3 Mac (kind)

This demo deploys **Kubeflow Pipelines standalone** (not the full reference platform) on a local `kind` cluster on your M3 MacBook Pro — the lightest path to a working KFP environment on Apple Silicon, avoiding the worst of the ARM64 image gaps that hit the full platform install.

> **Known M-series gotcha:** several `kubeflownotebookswg` and Model Registry dependency images (e.g., certain MySQL tags) lack arm64 manifests and will `ImagePullBackOff` on kind/Minikube on Apple Silicon. KFP's core pods (`ml-pipeline`, `seaweedfs`, `mysql:8.0.26` as used below, `workflow-controller`) are multi-arch and install cleanly. If you later add the full platform or Model Registry, expect to patch image tags — this is exactly the kind of work Kubeflow's own GSoC 2026 "ARM Support" track is targeting.

### 8.1 Prerequisites

```bash
# Already on your machine per your stack, but for completeness:
brew install kind kubectl kustomize
python3 -m venv ~/.venvs/kfp && source ~/.venvs/kfp/bin/activate
pip install kfp
```

### 8.2 Create a dedicated kind cluster

Keep this separate from `kind-devops-lab` so you're not fighting Confluent/Kargo resource pressure on the same node.

```bash
cat <<EOF | kind create cluster --name kubeflow-demo --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
EOF

kubectl cluster-info --context kind-kubeflow-demo
```

M3 sizing note: allocate at least 6 vCPU / 10 GB RAM to Docker Desktop / Colima before creating the cluster — KFP's MySQL, SeaweedFS, MLMD, and workflow-controller pods together need headroom beyond kind's defaults.

### 8.3 Install cert-manager

KFP's cache-server needs TLS certs. Using cert-manager avoids the cache-deployer's CSR-API dependency, which is finicky outside managed clouds too.

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.20.0/cert-manager.yaml
kubectl wait --for=condition=available --timeout=120s -n cert-manager deployment --all
```

### 8.4 Install KFP cluster-scoped resources

```bash
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=2.16.1"
kubectl wait --for=condition=established crd/applications.app.k8s.io --timeout=60s
```

### 8.5 Patch and deploy KFP

Create a local overlay (this is the same pattern as the DevOpsCube `mlops-for-devops` reference repo, adapted for kind instead of EKS):

```yaml
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kubeflow

resources:
  - github.com/kubeflow/pipelines/manifests/kustomize/env/platform-agnostic-emissary?ref=2.16.1

patches:
  - target:
      kind: Service
      name: ml-pipeline-ui
    patch: |
      - op: replace
        path: /spec/type
        value: NodePort
  - target:
      kind: Deployment
      name: seaweedfs
    patch: |
      - op: add
        path: /spec/template/spec/securityContext
        value:
          fsGroup: 1000
          runAsUser: 1000
          runAsGroup: 1000

# Remove cache-deployer; cert-manager issues the cache-server cert instead
patchesStrategicMerge: []
resources_to_remove:
  - cache-deployer  # apply via a separate `kubectl delete` if your kustomize version
                     # doesn't support component removal cleanly
```

```bash
kubectl apply -k .
kubectl get pods -n kubeflow -w
```

Expect `ml-pipeline`, `ml-pipeline-ui`, `mysql`, `seaweedfs`, `cache-server`, `metadata-grpc-deployment`, `metadata-writer`, and `workflow-controller` to reach `Running`. Some pods restart once or twice while dependencies settle — that's normal per the DevOpsCube guide.

### 8.6 Access the UI

```bash
kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8090:80
# → http://localhost:8090/#/pipelines
```

### 8.7 Author and run a pipeline from the KFP SDK

```python
# pipeline.py
from kfp import dsl, compiler, Client

@dsl.component(base_image="python:3.11-slim")
def preprocess(raw_rows: int) -> int:
    print(f"Simulating preprocessing of {raw_rows} rows")
    return raw_rows - 50  # pretend we dropped some bad rows

@dsl.component(base_image="python:3.11-slim")
def train(clean_rows: int) -> float:
    print(f"Training on {clean_rows} rows")
    return 0.91  # pretend accuracy

@dsl.component(base_image="python:3.11-slim")
def evaluate(accuracy: float):
    status = "PASS" if accuracy >= 0.85 else "FAIL"
    print(f"Eval result: {status} (accuracy={accuracy})")

@dsl.pipeline(name="m3-local-demo-pipeline")
def demo_pipeline(raw_rows: int = 1000):
    pre = preprocess(raw_rows=raw_rows)
    tr = train(clean_rows=pre.output)
    evaluate(accuracy=tr.output)

if __name__ == "__main__":
    compiler.Compiler().compile(demo_pipeline, "pipeline.yaml")

    client = Client(host="http://localhost:8090")
    run = client.create_run_from_pipeline_package(
        "pipeline.yaml",
        arguments={"raw_rows": 2000},
        run_name="m3-demo-run-1",
    )
    print(f"Run URL: http://localhost:8090/#/runs/details/{run.run_id}")
```

```bash
python pipeline.py
```

This compiles your Python DAG to IR YAML, submits it to the `ml-pipeline` API server, which creates an Argo Workflow CRD; the workflow controller schedules `system-dag-driver` → `system-container-driver` → `system-container-impl` pods per step, exactly as described in Section 4.3. Watch it execute live in the UI — each box in the graph is a real pod on your kind cluster.

### 8.8 GitOps-ifying it (production pattern)

For anything beyond this throwaway demo, point an ArgoCD `Application` at the same Kustomize overlay committed to Gitea instead of running `kubectl apply -k .` by hand:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kubeflow-pipelines
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://gitea.internal/platform-tools/kubeflow-pipeline.git
    targetRevision: main
    path: .
  destination:
    server: https://kubernetes.default.svc
    namespace: kubeflow
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### 8.9 Teardown

```bash
kind delete cluster --name kubeflow-demo
```

---

## 9. References (official documentation first)

1. Kubeflow Architecture — https://www.kubeflow.org/docs/started/architecture/
2. Kubeflow Introduction — https://www.kubeflow.org/docs/started/introduction/
3. Kubeflow Subprojects (official component index) — https://www.kubeflow.org/docs/components/
4. Kubeflow Pipelines Overview — https://www.kubeflow.org/docs/components/pipelines/overview/
5. Kubeflow Pipelines Installation (operator guide) — https://www.kubeflow.org/docs/components/pipelines/operator-guides/installation/
6. Kubeflow Trainer Overview — https://www.kubeflow.org/docs/components/trainer/overview/
7. Kubeflow Katib Overview — https://www.kubeflow.org/docs/components/katib/overview/
8. Kubeflow Hub (Model Registry) Overview — https://www.kubeflow.org/docs/components/hub/overview/
9. KServe (ecosystem) — https://www.kubeflow.org/docs/ecosystem/kserve/introduction/
10. Kubeflow Local Deployment (kind/K3s/Docker Desktop) — https://www.kubeflow.org/docs/components/pipelines/legacy-v1/installation/localcluster-deployment/
11. Kubeflow GSoC 2026 (ARM/Apple Silicon support project) — https://www.kubeflow.org/events/upcoming-events/gsoc-2026/
12. DevOpsCube — "Kubeflow for MLOps: A Practical Crash Course" — https://newsletter.devopscube.com/p/kubeflow-pipelines
13. DevOpsCube — "Set Up Kubeflow Pipelines on Kubernetes: Step-By-Step Guide" — https://devopscube.com/setup-kubeflow-pipelines-kubernetes/
14. Cloudflare — Inside Cloudflare's MLOps Platform — https://blog.cloudflare.com/mlops/
15. Kubeflow Pipelines GitHub manifests (Kustomize) — https://github.com/kubeflow/pipelines (path: `manifests/kustomize`)
16. cert-manager releases — https://cert-manager.io/docs/releases/
17. kind Quick Start — https://kind.sigs.k8s.io/docs/user/quick-start/
18. ARM64 image issue tracker (kubeflow/manifests #2472) — https://github.com/kubeflow/manifests/issues/2472
19. Apple Silicon KFP install field notes (Médéric Hurier / Fmind) — https://fmind.medium.com/how-to-install-kubeflow-on-apple-silicon-3565db8773f3
20. Kubeflow M3 Pro install field notes (community gist) — https://gist.github.com/lokeshrangineni/5af4b30e5b1e65b3e028e2221b6d76ff

*Secondary/comparison sources (not official docs, used for the competitor matrix in Section 6): mlai.qa MLOps Platform Comparison 2026, ZenML "MLflow Alternatives" blog, buildmvpfast.com W&B/MLflow/Kubeflow comparison, KodeKloud "Top 11 MLOps Tools 2026", Valohai MLOps Platforms Compared.*
