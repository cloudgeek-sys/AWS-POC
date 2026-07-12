from __future__ import annotations

import argparse
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

from pipelines.common.io_utils import ensure_dir, is_s3_uri, join_uri, list_s3_keys, read_dataset, read_json, write_csv, write_json, write_parquet
from pipelines.common.metrics import emit_metric
from pipelines.common.normalization import normalize_country, normalize_fuel
from pipelines.common.quality import (
    detect_schema_drift,
    load_schema,
    split_malformed_records,
    validate_uniqueness,
    validate_nulls,
    validate_ranges,
    validate_required_columns,
)


COUNTRY_REGION_MAP = {
    "United States": ("North America", "Northern America"),
    "United Kingdom": ("Europe", "Northern Europe"),
    "India": ("Asia", "Southern Asia"),
    "Germany": ("Europe", "Western Europe"),
    "France": ("Europe", "Western Europe"),
    "Brazil": ("South America", "South America"),
    "Canada": ("North America", "Northern America"),
    "China": ("Asia", "Eastern Asia"),
    "Australia": ("Oceania", "Australia and New Zealand"),
}

MANDATORY_NULL_CHECK_FIELDS = [
    "plant_name",
    "country",
    "primary_fuel",
    "capacity_mw",
]


def _latest_bronze_file(bronze_dir: str, source_name: str) -> str:
    if is_s3_uri(bronze_dir):
        parquet_keys = list_s3_keys(bronze_dir, suffix=".parquet")
        matches = sorted(
            k
            for k in parquet_keys
            if (
                k.rsplit("/", 1)[-1].startswith(f"{source_name}_")
                or k.rsplit("/", 1)[-1] == f"{source_name}.parquet"
            )
        )
    else:
        matches = sorted(
            str(p)
            for p in Path(bronze_dir).rglob("*.parquet")
            if (p.name.startswith(f"{source_name}_") or p.name == f"{source_name}.parquet")
        )
    if not matches:
        raise FileNotFoundError(f"No bronze data found for source {source_name}")
    return matches[-1]


def _latest_silver_file(silver_dir: str) -> str | None:
    target = join_uri(silver_dir, "stg_power_plants.parquet")
    if is_s3_uri(target):
        keys = list_s3_keys(silver_dir, suffix="stg_power_plants.parquet")
        return keys[-1] if keys else None
    path = Path(target)
    return str(path) if path.exists() else None


def _standardize_units(df: pd.DataFrame) -> pd.DataFrame:
    out = df.copy()
    if "capacity_mw" in out.columns:
        out["capacity_mw"] = pd.to_numeric(out["capacity_mw"], errors="coerce")

    if "capacity_unit" in out.columns and "capacity_mw" in out.columns:
        unit = out["capacity_unit"].astype(str).str.lower().str.strip()
        out.loc[unit.eq("kw"), "capacity_mw"] = out.loc[unit.eq("kw"), "capacity_mw"] / 1000.0
        out.loc[unit.eq("gw"), "capacity_mw"] = out.loc[unit.eq("gw"), "capacity_mw"] * 1000.0

    if "capacity_kw" in out.columns:
        kw = pd.to_numeric(out["capacity_kw"], errors="coerce")
        if "capacity_mw" not in out.columns:
            out["capacity_mw"] = kw / 1000.0
        else:
            out["capacity_mw"] = out["capacity_mw"].fillna(kw / 1000.0)

    if "capacity_gw" in out.columns:
        gw = pd.to_numeric(out["capacity_gw"], errors="coerce")
        if "capacity_mw" not in out.columns:
            out["capacity_mw"] = gw * 1000.0
        else:
            out["capacity_mw"] = out["capacity_mw"].fillna(gw * 1000.0)

    return out


def _enrich_geography(df: pd.DataFrame) -> pd.DataFrame:
    out = df.copy()
    lookup = out["country"].map(lambda c: COUNTRY_REGION_MAP.get(c, ("Other", "Other")))
    out["continent"] = lookup.str[0]
    out["sub_region"] = lookup.str[1]
    return out


def _ensure_canonical_columns(df: pd.DataFrame) -> pd.DataFrame:
    out = df.copy()

    if "plant_id" not in out.columns:
        if "gppd_idnr" in out.columns:
            out["plant_id"] = out["gppd_idnr"]
        elif "wepp_id" in out.columns:
            out["plant_id"] = out["wepp_id"]

    if "plant_name" not in out.columns and "name" in out.columns:
        out["plant_name"] = out["name"]

    if "country" in out.columns and "country_long" in out.columns:
        country_code = out["country"].astype(str).str.len().eq(3)
        out.loc[country_code, "country"] = out.loc[country_code, "country_long"]

    if "estimated_generation_gwh" not in out.columns:
        estimated_cols = sorted(
            [c for c in out.columns if c.startswith("estimated_generation_gwh_")],
            reverse=True,
        )
        if estimated_cols:
            out["estimated_generation_gwh"] = out[estimated_cols].bfill(axis=1).iloc[:, 0]

    return out


def run(data_root: str, schema_path: str) -> None:
    bronze_dir = join_uri(data_root, "bronze")
    silver_dir = join_uri(data_root, "silver")
    quarantine_dir = join_uri(data_root, "quarantine")
    audit_dir = join_uri(data_root, "audit")

    schema = load_schema(schema_path)

    source_candidates = ["wri_global_power_plants", "wri_power_plants"]
    latest_power_plants = None
    for candidate in source_candidates:
        try:
            latest_power_plants = _latest_bronze_file(bronze_dir, candidate)
            break
        except FileNotFoundError:
            continue
    if latest_power_plants is None:
        raise FileNotFoundError("No bronze data found for configured power plant source")
    df = read_dataset(latest_power_plants, "parquet")
    df = _ensure_canonical_columns(df)

    missing_required = validate_required_columns(df, schema["required_columns"])
    if missing_required:
        raise ValueError(f"Missing required columns: {missing_required}")

    df = _standardize_units(df)

    df["country"] = df["country"].apply(normalize_country)
    df["primary_fuel"] = df["primary_fuel"].apply(normalize_fuel)
    df = _enrich_geography(df)

    for col in schema["numeric_columns"]:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")

    valid_df, malformed_df = split_malformed_records(
        df,
        schema["required_columns"],
        schema["range_rules"],
    )

    uniqueness_pre_upsert = validate_uniqueness(valid_df, "plant_id")
    duplicate_rows = int(uniqueness_pre_upsert["duplicate_count"])

    # Keep latest record per plant_id in current batch.
    valid_df = valid_df.sort_values("ingested_at").drop_duplicates(subset=["plant_id"], keep="last")

    # Incremental upsert: merge current batch into existing silver table by plant_id.
    existing_silver_path = _latest_silver_file(silver_dir)
    if existing_silver_path:
        existing_df = read_dataset(existing_silver_path, "parquet")
        if "plant_id" in existing_df.columns:
            combined = pd.concat([existing_df, valid_df], ignore_index=True, sort=False)
            if "event_time" in combined.columns:
                combined["_event_time_sort"] = pd.to_datetime(combined["event_time"], errors="coerce")
            else:
                combined["_event_time_sort"] = pd.NaT
            if "ingested_at" in combined.columns:
                combined["_ingest_sort"] = pd.to_datetime(combined["ingested_at"], errors="coerce")
            else:
                combined["_ingest_sort"] = pd.NaT
            valid_df = (
                combined
                .sort_values(["_event_time_sort", "_ingest_sort"])
                .drop_duplicates(subset=["plant_id"], keep="last")
                .drop(columns=["_event_time_sort", "_ingest_sort"], errors="ignore")
            )

    uniqueness_post_upsert = validate_uniqueness(valid_df, "plant_id")

    if "event_time" in valid_df.columns:
        event_time = pd.to_datetime(valid_df["event_time"], errors="coerce")
    else:
        event_time = pd.to_datetime(valid_df.get("last_updated_at"), errors="coerce")
    valid_df["event_year"] = event_time.dt.year.fillna(pd.Timestamp.now().year).astype(int)
    valid_df["event_month"] = event_time.dt.month.fillna(1).astype(int)

    out_good = join_uri(silver_dir, "stg_power_plants.parquet")
    out_bad = join_uri(quarantine_dir, "stg_power_plants_malformed.parquet")
    write_parquet(valid_df, out_good)
    write_parquet(malformed_df, out_bad)

    null_issues = validate_nulls(df, schema["required_columns"])
    mandatory_null_issues = validate_nulls(df, MANDATORY_NULL_CHECK_FIELDS)
    range_issues = validate_ranges(df, schema["range_rules"])
    positive_capacity_ok = int(range_issues.get("capacity_mw", 0)) == 0
    valid_commissioning_year_ok = int(range_issues.get("commissioning_year", 0)) == 0
    mandatory_fields_ok = (len(missing_required) == 0) and (len(null_issues) == 0)
    mandatory_null_validation_ok = len(mandatory_null_issues) == 0

    schema_state_path = join_uri(audit_dir, "silver_schema_state.json")
    previous_schema_state = read_json(schema_state_path)
    previous_columns = previous_schema_state.get("columns", [])
    current_columns = sorted(valid_df.columns.tolist())
    drift = detect_schema_drift(previous_columns, current_columns) if previous_columns else {
        "schema_drift_detected": False,
        "new_columns": [],
        "removed_columns": [],
    }
    write_json({"columns": current_columns}, schema_state_path)

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
                "duplicate_rows_detected": duplicate_rows,
                "unique_plant_id_ok": bool(uniqueness_post_upsert["is_unique"]),
                "duplicate_plant_id_count": int(uniqueness_post_upsert["duplicate_count"]),
                "mandatory_fields_ok": mandatory_fields_ok,
                "mandatory_null_validation_ok": mandatory_null_validation_ok,
                "null_plant_name": int(mandatory_null_issues.get("plant_name", 0)),
                "null_country": int(mandatory_null_issues.get("country", 0)),
                "null_primary_fuel": int(mandatory_null_issues.get("primary_fuel", 0)),
                "null_capacity_mw": int(mandatory_null_issues.get("capacity_mw", 0)),
                "positive_capacity_ok": positive_capacity_ok,
                "invalid_capacity_rows": int(range_issues.get("capacity_mw", 0)),
                "valid_commissioning_year_ok": valid_commissioning_year_ok,
                "invalid_commissioning_year_rows": int(range_issues.get("commissioning_year", 0)),
                "schema_drift_detected": drift["schema_drift_detected"],
                "schema_new_columns": str(drift["new_columns"]),
                "schema_removed_columns": str(drift["removed_columns"]),
                "null_issues": str(null_issues),
                "range_issues": str(range_issues),
            }
        ]
        ),
        join_uri(audit_dir, "silver_quality_report.csv"),
    )

    emit_metric(join_uri(audit_dir, "metrics.csv"), "silver_valid_rows", float(len(valid_df)))
    emit_metric(join_uri(audit_dir, "metrics.csv"), "dq_failure_count", float(len(malformed_df)))
    emit_metric(join_uri(audit_dir, "metrics.csv"), "silver_duplicate_rows_detected", float(duplicate_rows))
    emit_metric(
        join_uri(audit_dir, "metrics.csv"),
        "silver_unique_plant_id_ok",
        float(1.0 if uniqueness_post_upsert["is_unique"] else 0.0),
    )
    emit_metric(
        join_uri(audit_dir, "metrics.csv"),
        "silver_duplicate_plant_id_count",
        float(uniqueness_post_upsert["duplicate_count"]),
    )
    emit_metric(
        join_uri(audit_dir, "metrics.csv"),
        "silver_mandatory_null_validation_ok",
        float(1.0 if mandatory_null_validation_ok else 0.0),
    )
    emit_metric(join_uri(audit_dir, "metrics.csv"), "silver_null_plant_name", float(mandatory_null_issues.get("plant_name", 0)))
    emit_metric(join_uri(audit_dir, "metrics.csv"), "silver_null_country", float(mandatory_null_issues.get("country", 0)))
    emit_metric(
        join_uri(audit_dir, "metrics.csv"),
        "silver_null_primary_fuel",
        float(mandatory_null_issues.get("primary_fuel", 0)),
    )
    emit_metric(join_uri(audit_dir, "metrics.csv"), "silver_null_capacity_mw", float(mandatory_null_issues.get("capacity_mw", 0)))
    emit_metric(join_uri(audit_dir, "metrics.csv"), "silver_positive_capacity_ok", float(1.0 if positive_capacity_ok else 0.0))
    emit_metric(join_uri(audit_dir, "metrics.csv"), "silver_invalid_capacity_rows", float(range_issues.get("capacity_mw", 0)))
    emit_metric(
        join_uri(audit_dir, "metrics.csv"),
        "silver_valid_commissioning_year_ok",
        float(1.0 if valid_commissioning_year_ok else 0.0),
    )
    emit_metric(
        join_uri(audit_dir, "metrics.csv"),
        "silver_invalid_commissioning_year_rows",
        float(range_issues.get("commissioning_year", 0)),
    )
    emit_metric(join_uri(audit_dir, "metrics.csv"), "silver_mandatory_fields_ok", float(1.0 if mandatory_fields_ok else 0.0))
    emit_metric(
        join_uri(audit_dir, "metrics.csv"),
        "silver_schema_drift_detected",
        float(1.0 if drift["schema_drift_detected"] else 0.0),
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Silver transform for power plant datasets")
    parser.add_argument("--data-root", default="artifacts/local")
    parser.add_argument("--schema", default="pipelines/schemas/power_plants_schema.json")
    args, _ = parser.parse_known_args()
    return args


if __name__ == "__main__":
    args = parse_args()
    run(args.data_root, args.schema)
