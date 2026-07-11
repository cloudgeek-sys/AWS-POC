from __future__ import annotations

import argparse
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

from pipelines.common.io_utils import ensure_dir, is_s3_uri, join_uri, list_s3_keys, read_dataset, write_csv, write_parquet
from pipelines.common.metrics import emit_local_metric
from pipelines.common.normalization import normalize_country, normalize_fuel
from pipelines.common.quality import (
    load_schema,
    split_malformed_records,
    validate_nulls,
    validate_ranges,
    validate_required_columns,
)


def _latest_bronze_file(bronze_dir: str, source_name: str) -> str:
    if is_s3_uri(bronze_dir):
        matches = sorted(list_s3_keys(bronze_dir, suffix=f"{source_name}.parquet"))
    else:
        matches = sorted(str(p) for p in Path(bronze_dir).rglob(f"{source_name}.parquet"))
    if not matches:
        raise FileNotFoundError(f"No bronze data found for source {source_name}")
    return matches[-1]


def run(data_root: str, schema_path: str) -> None:
    bronze_dir = join_uri(data_root, "bronze")
    silver_dir = join_uri(data_root, "silver")
    quarantine_dir = join_uri(data_root, "quarantine")
    audit_dir = join_uri(data_root, "audit")

    schema = load_schema(schema_path)

    latest_power_plants = _latest_bronze_file(bronze_dir, "wri_power_plants")
    df = read_dataset(latest_power_plants, "parquet")

    missing_required = validate_required_columns(df, schema["required_columns"])
    if missing_required:
        raise ValueError(f"Missing required columns: {missing_required}")

    df["country"] = df["country"].apply(normalize_country)
    df["primary_fuel"] = df["primary_fuel"].apply(normalize_fuel)

    for col in schema["numeric_columns"]:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")

    valid_df, malformed_df = split_malformed_records(
        df,
        schema["required_columns"],
        schema["range_rules"],
    )

    # keep latest record per plant_id using ingest timestamp
    valid_df = valid_df.sort_values("ingested_at").drop_duplicates(subset=["plant_id"], keep="last")

    event_time = pd.to_datetime(valid_df.get("last_updated_at"), errors="coerce")
    valid_df["event_year"] = event_time.dt.year.fillna(pd.Timestamp.now().year).astype(int)
    valid_df["event_month"] = event_time.dt.month.fillna(1).astype(int)

    out_good = join_uri(silver_dir, "stg_power_plants.parquet")
    out_bad = join_uri(quarantine_dir, "stg_power_plants_malformed.parquet")
    write_parquet(valid_df, out_good)
    write_parquet(malformed_df, out_bad)

    null_issues = validate_nulls(df, schema["required_columns"])
    range_issues = validate_ranges(df, schema["range_rules"])

    if not is_s3_uri(audit_dir):
        ensure_dir(Path(audit_dir))
    write_csv(
        pd.DataFrame(
        [
            {
                "run_timestamp": datetime.now(timezone.utc).isoformat(),
                "dataset": "stg_power_plants",
                "input_rows": int(len(df)),
                "valid_rows": int(len(valid_df)),
                "malformed_rows": int(len(malformed_df)),
                "null_issues": str(null_issues),
                "range_issues": str(range_issues),
            }
        ]
        ),
        join_uri(audit_dir, "silver_quality_report.csv"),
    )

    emit_local_metric(join_uri(audit_dir, "metrics.csv"), "silver_valid_rows", float(len(valid_df)))
    emit_local_metric(join_uri(audit_dir, "metrics.csv"), "dq_failure_count", float(len(malformed_df)))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Silver transform for power plant datasets")
    parser.add_argument("--data-root", default="artifacts/local")
    parser.add_argument("--schema", default="pipelines/schemas/power_plants_schema.json")
    args, _ = parser.parse_known_args()
    return args


if __name__ == "__main__":
    args = parse_args()
    run(args.data_root, args.schema)
