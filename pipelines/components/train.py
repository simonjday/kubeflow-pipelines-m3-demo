from kfp import dsl


@dsl.component(base_image="python:3.11-slim")
def train(clean_rows: int) -> float:
    """Simulates a model training step and returns a fake accuracy score."""
    print(f"Training on {clean_rows} rows")
    # Pretend accuracy scales (very loosely) with available training data.
    accuracy = min(0.99, 0.7 + (clean_rows / 10000))
    print(f"Training complete. accuracy={accuracy:.4f}")
    return accuracy
