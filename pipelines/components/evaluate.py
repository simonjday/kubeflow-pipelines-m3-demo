from kfp import dsl


@dsl.component(base_image="python:3.11-slim")
def evaluate(accuracy: float, threshold: float = 0.85) -> str:
    """Simulates a model evaluation gate against a minimum accuracy threshold."""
    status = "PASS" if accuracy >= threshold else "FAIL"
    print(f"Eval result: {status} (accuracy={accuracy:.4f}, threshold={threshold})")
    return status
