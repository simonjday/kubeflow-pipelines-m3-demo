# Kubeflow in 2026: What It Actually Is, and Whether It Deserves a Slot in Your GitOps Stack

I run a homelab kind cluster the way some people run a workshop: ArgoCD syncing from Gitea, Kyverno enforcing policy, Confluent Platform handling event streams, Kargo doing progressive delivery. So when I sat down to actually understand Kubeflow properly — not the marketing page, the architecture — I wanted to know one thing: does this slot into a GitOps-first Kubernetes platform, or is it another walled garden pretending to be Kubernetes-native?

Short answer: it slots in better than I expected, with one big caveat about scope.

## It's not one thing anymore

Kubeflow started in 2017 as a Google side project to run TensorFlow jobs on Kubernetes — the name is literally "Kube" + "Flow." For years it shipped as a monolithic install: one big manifest pile, Istio and Dex baked in whether you wanted multi-tenant auth or not.

That changed meaningfully with the 1.11 release in December 2025. Kubeflow now ships as **nine independently installable subprojects** — SDK, Spark Operator, Notebooks, Trainer, Katib, Hub (the renamed Model Registry), Pipelines, Dashboard, and Kale — each with its own component-based Helm chart. You can install just Kubeflow Pipelines and Kubeflow Trainer and skip the rest entirely. That's the difference between "adopting a platform" and "adopting a Kubernetes-native primitive," and it's the right direction.

The other notable repositioning: Kubeflow's own docs now describe it as the **Kubeflow AI Reference Platform**, with explicit emphasis on GenAI, distributed LLM training, and fine-tuning — not just classical ML pipelines anymore.

## The part that actually matters: Kubeflow Pipelines runs on Argo

Here's the architectural detail that clicked things into place for me. Kubeflow Pipelines doesn't invent its own workflow engine — it compiles your Python-defined DAG into an Intermediate Representation YAML, submits it as an **Argo Workflow CRD**, and lets the Argo workflow controller schedule the actual pods. If you already run Argo Workflows or ArgoCD, you already understand 80% of how KFP executes things.

What KFP adds on top of bare Argo is the ML-aware layer Argo doesn't know about: artifact and metric tracking via ML Metadata (MLMD), task-level result caching (so a failed pipeline doesn't have to re-run from scratch), and a UI that understands "experiment" and "run" as concepts, not just "workflow."

That's a genuinely useful abstraction if you're orchestrating multi-step ML pipelines on Kubernetes already. It's a much weaker argument if all you need is experiment tracking — which is exactly why MLflow has effectively won that specific niche, and most teams in 2026 wire MLflow into KFP rather than relying on KFP's own metadata UI.

## Where it loses, and to whom

No platform wins outright in the 2026 MLOps landscape, and I think that's worth saying plainly rather than hedging:

- **MLflow** wins on experiment tracking and model registry UX, full stop, and it doesn't need a Kubernetes cluster to do it.
- **Flyte** is increasingly the default pick for greenfield Kubernetes-native pipeline projects, with stronger typed data contracts than KFP v1 ever had.
- **SageMaker / Vertex AI / Azure ML** win decisively if you've already standardized on one cloud and want zero cluster operations — though notably, Vertex AI Pipelines is built on the same underlying tech as KFP, so you're not really escaping the architecture, just outsourcing the ops.
- **Ray/KubeRay** has taken over a lot of the distributed-training mindshare that used to belong to Kubeflow Training Operator.

Kubeflow's actual edge is narrower and more specific than the marketing suggests: **you want Kubernetes-native, multi-cloud or on-prem, GitOps-manageable ML orchestration, and you're not willing to hand a cloud vendor your training pipeline.** If that's not your constraint, there's probably a better-fit tool above.

## Running it on Apple Silicon is still a tax

If you want to try this locally, the honest caveat: ARM64 support is uneven. Several images under `kubeflownotebookswg` and some Model Registry dependencies (older MySQL tags, specifically) don't ship arm64 manifests, and you'll hit `ImagePullBackOff` on a kind or Minikube cluster on an M-series Mac. It's annoying enough that it's literally a tracked Google Summer of Code 2026 project for the Kubeflow community — "Golden Data" configs and full end-to-end ARM test suites are explicitly being built because this gap is well known.

The workaround that actually works: install **Kubeflow Pipelines standalone** rather than the full reference platform. KFP's core pods — `ml-pipeline`, the workflow controller, SeaweedFS, a recent MySQL tag — are multi-arch and install cleanly on kind. You lose the central dashboard and multi-tenant auth, but you get a working pipeline orchestrator you can actually run and iterate on from a MacBook.

## The verdict

Kubeflow earns its complexity if your team already operates Kubernetes as a platform — meaning you have the appetite for CRDs, controllers, and Kustomize/Helm-based GitOps, and you're not looking for a turnkey SaaS. If that's you, install Pipelines and Trainer, wire in MLflow for tracking, point KServe at your trained models, and manage the whole thing as just another ArgoCD Application alongside everything else you already run. If that's not you — if you want a model registry and nothing else, or you've already bet the farm on one cloud — there's a simpler, cheaper tool with your name on it.

---

*Sources: kubeflow.org official documentation (architecture, components, Pipelines, Trainer); DevOpsCube's MLOps newsletter series; Kubeflow's GSoC 2026 project list; Cloudflare Engineering's public writeup of their internal MLOps platform.*
