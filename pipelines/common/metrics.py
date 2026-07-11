from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from pipelines.common.io_utils import append_text, ensure_dir, is_s3_uri


def emit_local_metric(metric_file: Path, metric_name: str, value: float) -> None:
    ts = datetime.now(timezone.utc).isoformat()
    if not is_s3_uri(metric_file):
        ensure_dir(Path(metric_file).parent)
    append_text(metric_file, f"{ts},{metric_name},{value}\n")
