from __future__ import annotations

from datetime import datetime, timezone
import math
import os
from pathlib import Path

import boto3
from botocore.exceptions import BotoCoreError, ClientError

from pipelines.common.io_utils import append_text, ensure_dir, is_s3_uri


ALLOWED_METRIC_PREFIXES = (
    "bronze_",
    "silver_",
    "gold_",
    "freshness_",
    "volume_",
    "dq_",
    "visualizations_",
    "renewable_",
)

ALLOWED_METRIC_EXACT = {
    "dq_failure_count",
    "renewable_energy_ratio",
}


def _is_metric_allowed(metric_name: str) -> bool:
    return metric_name in ALLOWED_METRIC_EXACT or metric_name.startswith(ALLOWED_METRIC_PREFIXES)


def emit_local_metric(metric_file: Path, metric_name: str, value: float) -> None:
    if not _is_metric_allowed(metric_name):
        raise ValueError(f"Metric name '{metric_name}' is not allowed by restricted metrics policy")
    if not math.isfinite(float(value)):
        raise ValueError(f"Metric value for '{metric_name}' must be finite")

    ts = datetime.now(timezone.utc).isoformat()
    if not is_s3_uri(metric_file):
        ensure_dir(Path(metric_file).parent)
    append_text(metric_file, f"{ts},{metric_name},{value}\n")


def emit_cloudwatch_metric(metric_name: str, value: float) -> None:
    if not _is_metric_allowed(metric_name):
        raise ValueError(f"Metric name '{metric_name}' is not allowed by restricted metrics policy")
    if not math.isfinite(float(value)):
        raise ValueError(f"Metric value for '{metric_name}' must be finite")

    if os.getenv("DISABLE_CLOUDWATCH_METRICS", "false").lower() == "true":
        return

    namespace = os.getenv("CLOUDWATCH_METRIC_NAMESPACE", "GPPA/Pipeline")
    project_name = os.getenv("GPPA_PROJECT_NAME", "gppa")
    environment = os.getenv("GPPA_ENVIRONMENT", "local")
    region = os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION") or "us-east-1"

    try:
        cw = boto3.client("cloudwatch", region_name=region)
        cw.put_metric_data(
            Namespace=namespace,
            MetricData=[
                {
                    "MetricName": metric_name,
                    "Dimensions": [
                        {"Name": "Project", "Value": project_name},
                        {"Name": "Environment", "Value": environment},
                    ],
                    "Timestamp": datetime.now(timezone.utc),
                    "Value": float(value),
                    "Unit": "Count",
                }
            ],
        )
    except (BotoCoreError, ClientError) as exc:
        if os.getenv("METRICS_STRICT_MODE", "false").lower() == "true":
            raise RuntimeError(f"Failed to publish CloudWatch metric '{metric_name}': {exc}") from exc
        print(f"WARNING: CloudWatch metric publish skipped for '{metric_name}': {exc}")


def emit_metric(metric_file: Path, metric_name: str, value: float) -> None:
    emit_local_metric(metric_file, metric_name, value)
    emit_cloudwatch_metric(metric_name, value)
