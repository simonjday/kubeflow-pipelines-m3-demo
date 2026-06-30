"""
m3-local-demo-pipeline

Compiles a 3-step KFP pipeline (preprocess -> train -> evaluate) and submits
it to a Kubeflow Pipelines instance reachable at KFP_ENDPOINT.

Usage:
    kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8090:80
    python pipeline.py
"""
import os

from kfp import dsl, compiler, Client

from components.preprocess import preprocess
from components.train import train
from components.evaluate import evaluate

KFP_ENDPOINT = os.environ.get("KFP_ENDPOINT", "http://localhost:8090")
COMPILED_PATH = os.environ.get("COMPILED_PATH", "pipeline.yaml")


@dsl.pipeline(name="m3-local-demo-pipeline")
def demo_pipeline(raw_rows: int = 1000, accuracy_threshold: float = 0.85):
    pre = preprocess(raw_rows=raw_rows)
    tr = train(clean_rows=pre.output)
    evaluate(accuracy=tr.output, threshold=accuracy_threshold)


def main() -> None:
    compiler.Compiler().compile(demo_pipeline, COMPILED_PATH)
    print(f"Compiled pipeline IR written to {COMPILED_PATH}")

    client = Client(host=KFP_ENDPOINT)
    run = client.create_run_from_pipeline_package(
        COMPILED_PATH,
        arguments={"raw_rows": 2000, "accuracy_threshold": 0.85},
        run_name="m3-demo-run-1",
    )
    print(f"Run submitted: {run.run_id}")
    print(f"Run URL: {KFP_ENDPOINT}/#/runs/details/{run.run_id}")


if __name__ == "__main__":
    main()
