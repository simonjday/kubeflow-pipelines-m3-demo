from kfp import dsl


@dsl.component(base_image="python:3.11-slim")
def preprocess(raw_rows: int) -> int:
    """Simulates a data preprocessing step: ingest, validate, drop bad rows."""
    dropped = 50
    clean_rows = raw_rows - dropped
    print(f"Ingested {raw_rows} rows, dropped {dropped} invalid rows, "
          f"{clean_rows} rows remain")
    return clean_rows
