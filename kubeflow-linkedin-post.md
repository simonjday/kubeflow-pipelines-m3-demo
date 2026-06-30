Spent the week digging into Kubeflow's architecture properly instead of skimming the marketing page. A few things worth sharing for anyone running Kubernetes-native platforms:

🔹 Kubeflow Pipelines doesn't have its own execution engine — it compiles your Python DAG to an IR YAML and submits it as an Argo Workflow CRD. If you already run Argo, you already understand most of how KFP actually executes.

🔹 As of the 1.11 release (Dec 2025), Kubeflow ships as 9 independently installable subprojects with component-based Helm charts — install just Pipelines + Trainer, skip the Istio/Dex-heavy full platform if you don't need multi-tenant auth.

🔹 It's been repositioned as the "Kubeflow AI Reference Platform" — less classical-MLOps, more distributed LLM training and fine-tuning focus.

🔹 Honest gap: ARM64/Apple Silicon support is still uneven. Several images lack arm64 manifests — it's literally a tracked GSoC 2026 project. Workaround: install KFP standalone rather than the full platform; the core pods are multi-arch and run fine on a local kind cluster.

🔹 No platform wins outright in 2026 — MLflow has effectively won experiment tracking/registry, Flyte is the default pick for a lot of greenfield pipeline work, and most teams now wire MLflow into KFP rather than relying on its native tracking UI.

Where Kubeflow actually earns its complexity: Kubernetes-native, multi-cloud or on-prem, GitOps-manageable ML orchestration — for teams not willing to hand a cloud vendor their training pipeline. If that's not your constraint, there's probably a simpler tool with your name on it.

Wrote up the full architecture breakdown, pros/cons, a competitor comparison (MLflow, SageMaker, Vertex AI, Flyte, ZenML, Databricks), and an end-to-end local demo running KFP on a kind cluster on an M3 Mac — link in comments.

#Kubernetes #MLOps #Kubeflow #GitOps #PlatformEngineering #DevOps
