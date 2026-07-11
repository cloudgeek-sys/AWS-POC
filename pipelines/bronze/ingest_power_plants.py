from __future__ import annotations

import argparse
import hashlib
import io
import json
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import pandas as pd
import pyarrow.parquet as pq
import yaml

from pipelines.common.io_utils import file_hash, join_uri, read_dataset, read_text, write_csv, write_parquet
from pipelines.common.metrics import emit_metric
from pipelines.common.state_store import StateStore


def _parse_ts(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value)
    except Exception:
        return None


def _build_freshness_report(config: dict, state_store: StateStore, ingest_results: list[dict]) -> pd.DataFrame:
    now = datetime.now(timezone.utc)
    result_by_source = {r.get("source_name"): r for r in ingest_results}

    rows: list[dict] = []
    for source in config["sources"]:
        source_name = source["source_name"]
        src_state = state_store.get_source(source_name)
        source_result = result_by_source.get(source_name, {})

        update_sla_hours = float(source.get("freshness_update_sla_hours", 24.0))
        delay_sla_hours = float(source.get("freshness_ingestion_delay_sla_hours", 24.0))

        last_ingested_at = _parse_ts(src_state.get("last_ingested_at"))
        event_watermark = _parse_ts(src_state.get("event_time_watermark"))

        if last_ingested_at is None:
            hours_since_update = None
            missing_updates = True
        else:
            hours_since_update = (now - last_ingested_at).total_seconds() / 3600.0
            missing_updates = hours_since_update > update_sla_hours

        ingestion_delay_hours = None
        ingestion_delay_breached = False
        if last_ingested_at is not None and event_watermark is not None:
            ingestion_delay_hours = max(0.0, (last_ingested_at - event_watermark).total_seconds() / 3600.0)
            ingestion_delay_breached = ingestion_delay_hours > delay_sla_hours

        rows.append(
            {
                "run_timestamp": now.isoformat(),
                "source_name": source_name,
                "ingest_status": source_result.get("status", "unknown"),
                "last_ingested_at": src_state.get("last_ingested_at"),
                "event_time_watermark": src_state.get("event_time_watermark"),
                "update_sla_hours": update_sla_hours,
                "hours_since_last_update": None if hours_since_update is None else round(hours_since_update, 4),
                "missing_updates": bool(missing_updates),
                "ingestion_delay_sla_hours": delay_sla_hours,
                "ingestion_delay_hours": None if ingestion_delay_hours is None else round(ingestion_delay_hours, 4),
                "ingestion_delay_breached": bool(ingestion_delay_breached),
            }
        )

    return pd.DataFrame(rows)


def _evaluate_volume_change(
    current_rows: int,
    previous_rows: int | None,
    spike_threshold_ratio: float,
    drop_threshold_ratio: float,
) -> tuple[float | None, bool, bool]:
    if previous_rows is None or previous_rows <= 0:
        return None, False, False

    ratio = float(current_rows) / float(previous_rows)
    is_spike = ratio >= spike_threshold_ratio
    is_drop = ratio <= drop_threshold_ratio
    return ratio, is_spike, is_drop


def _kagglehub_dataset_hash(df: pd.DataFrame) -> str:
    digest = hashlib.sha256()
    digest.update(df.to_csv(index=False).encode("utf-8"))
    return digest.hexdigest()


def _row_hash(df: pd.DataFrame, columns: list[str] | None = None) -> pd.Series:
    # Hash row content to detect per-record changes across incremental loads.
    # Use aligned columns to tolerate additive/dropped columns over time.
    aligned_columns = sorted(columns or list(df.columns))
    aligned = df.reindex(columns=aligned_columns).astype("string").fillna("")
    return pd.util.hash_pandas_object(aligned, index=False).astype("string")


def _navigate_path(payload: object, dotted_path: str) -> object:
    current = payload
    for part in dotted_path.split("."):
        if isinstance(current, dict) and part in current:
            current = current[part]
            continue
        raise KeyError(f"Could not resolve data_path '{dotted_path}' in API response")
    return current


def _read_api_dataset(source: dict) -> tuple[pd.DataFrame, str]:
    api_url = source.get("url")
    if not api_url:
        raise ValueError("API source must define 'url'")

    method = str(source.get("method", "GET")).upper()
    headers = source.get("headers", {})
    params = source.get("params", {})
    timeout_seconds = int(source.get("timeout_seconds", 60))

    if params:
        delimiter = "&" if "?" in api_url else "?"
        api_url = f"{api_url}{delimiter}{urlencode(params)}"

    payload_bytes: bytes | None = None
    json_payload = source.get("json_payload")
    if json_payload is not None:
        payload_bytes = json.dumps(json_payload).encode("utf-8")
        headers = {**headers, "Content-Type": "application/json"}

    request = Request(api_url, data=payload_bytes, method=method)
    for key, value in headers.items():
        request.add_header(str(key), str(value))

    with urlopen(request, timeout=timeout_seconds) as response:
        raw = response.read()

    response_format = str(source.get("response_format", "json")).lower()
    pandas_kwargs = source.get("pandas_kwargs", {})

    if response_format == "csv":
        df = pd.read_csv(io.BytesIO(raw), **pandas_kwargs)
    elif response_format == "parquet":
        table = pq.read_table(io.BytesIO(raw))
        df = table.to_pandas()
    elif response_format == "json":
        parsed = json.loads(raw.decode("utf-8"))
        data_path = source.get("data_path")
        if data_path:
            parsed = _navigate_path(parsed, data_path)
        if isinstance(parsed, list):
            df = pd.DataFrame(parsed)
        elif isinstance(parsed, dict):
            df = pd.DataFrame([parsed])
        else:
            raise ValueError("API JSON response must resolve to an object or array")
    else:
        raise ValueError(f"Unsupported API response_format: {response_format}")

    digest = hashlib.sha256()
    digest.update(raw)
    return df, digest.hexdigest()


def _safe_read_previous_output(path: str | None) -> pd.DataFrame | None:
    if not path:
        return None
    try:
        return read_dataset(path, "parquet")
    except Exception:
        return None


def _compute_changed_records(current: pd.DataFrame, previous: pd.DataFrame | None, primary_key: str | None) -> pd.DataFrame:
    if previous is None or not primary_key or primary_key not in current.columns:
        return current

    if primary_key not in previous.columns:
        return current

    curr = current.copy()
    prev = previous.copy()

    compare_columns = sorted(set(curr.columns).union(set(prev.columns)))

    curr["_row_hash"] = _row_hash(curr, compare_columns)
    prev["_row_hash_prev"] = _row_hash(prev, compare_columns)

    merged = curr.merge(
        prev[[primary_key, "_row_hash_prev"]],
        on=primary_key,
        how="left",
    )
    changed = merged[merged["_row_hash"] != merged["_row_hash_prev"]].drop(columns=["_row_hash", "_row_hash_prev"])
    return changed


def _apply_event_time_annotations(df: pd.DataFrame, event_time_column: str | None, previous_watermark: str | None) -> tuple[pd.DataFrame, str | None]:
    out = df.copy()
    if not event_time_column or event_time_column not in out.columns:
        out["event_time"] = pd.NaT
        out["is_late_arriving"] = False
        return out, previous_watermark

    out["event_time"] = pd.to_datetime(out[event_time_column], errors="coerce", utc=True)

    previous_ts = pd.to_datetime(previous_watermark, utc=True, errors="coerce") if previous_watermark else pd.NaT
    if pd.isna(previous_ts):
        out["is_late_arriving"] = False
    else:
        out["is_late_arriving"] = out["event_time"] < previous_ts

    current_max = out["event_time"].max()
    if pd.isna(current_max):
        return out, previous_watermark

    if pd.isna(previous_ts) or current_max > previous_ts:
        return out, current_max.isoformat()
    return out, previous_watermark


def _read_source_dataset(source: dict, source_base: str) -> tuple[pd.DataFrame, str]:
    file_format = source["format"].lower()

    if file_format == "api":
        return _read_api_dataset(source)

    if file_format == "kagglehub":
        try:
            import kagglehub
            from kagglehub import KaggleDatasetAdapter
        except Exception as exc:  # pragma: no cover - import error depends on env
            raise RuntimeError(
                "kagglehub is required for format='kagglehub'. Install with: pip install \"kagglehub[pandas-datasets]\""
            ) from exc

        dataset = source.get("dataset")
        file_path = source.get("file_path", "")

        if not dataset:
            raise ValueError("Kaggle source must define 'dataset', for example: jaytilala/global-power-plant")

        pandas_kwargs = source.get("pandas_kwargs", {})
        df: pd.DataFrame | None = None

        if file_path:
            try:
                df = kagglehub.load_dataset(
                    KaggleDatasetAdapter.PANDAS,
                    dataset,
                    file_path,
                    pandas_kwargs=pandas_kwargs,
                )
            except Exception:
                df = None

        # Fallback mode: download dataset and auto-pick first CSV.
        if df is None:
            download_path = Path(kagglehub.dataset_download(dataset))
            csv_files = sorted(download_path.rglob("*.csv"))
            if not csv_files:
                raise FileNotFoundError(
                    f"No CSV files found in Kaggle dataset '{dataset}'. Set source.file_path explicitly in sources.yaml."
                )
            df = pd.read_csv(csv_files[0], **pandas_kwargs)

        return df, _kagglehub_dataset_hash(df)

    source_path = join_uri(source_base, source["path"])
    df = read_dataset(source_path, file_format)
    return df, file_hash(source_path)


def _ingest_one_source(
    source: dict,
    source_base: str,
    bronze_dir: str,
    state_store: StateStore,
    force_replay: bool,
) -> dict:
    source_name = source["source_name"]

    src_state = state_store.get_source(source_name)
    df, src_hash = _read_source_dataset(source, source_base)
    previous_rows = src_state.get("last_rows")
    spike_threshold_ratio = float(source.get("volume_spike_threshold_ratio", 2.0))
    drop_threshold_ratio = float(source.get("volume_drop_threshold_ratio", 0.5))

    if not force_replay and src_state.get("last_file_hash") == src_hash:
        state_store.upsert_source(
            source_name,
            {
                "last_status": "skipped",
                "last_checked_at": datetime.now(timezone.utc).isoformat(),
                "last_rows": int(len(df)),
            },
        )
        return {
            "source_name": source_name,
            "status": "skipped",
            "rows": 0,
            "changed_rows": 0,
            "late_arriving_rows": 0,
            "volume_ratio": None,
            "volume_spike_detected": False,
            "volume_drop_detected": False,
        }

    previous_output = _safe_read_previous_output(src_state.get("last_output_path"))
    primary_key = source.get("primary_key")
    event_time_column = source.get("event_time_column")
    changed_df = _compute_changed_records(df, previous_output, primary_key)

    if not force_replay and len(changed_df) == 0:
        state_store.upsert_source(
            source_name,
            {
                "last_file_hash": src_hash,
                "last_checked_at": datetime.now(timezone.utc).isoformat(),
                "last_status": "no_changes",
                "last_rows": int(len(df)),
            },
        )
        return {
            "source_name": source_name,
            "status": "no_changes",
            "rows": 0,
            "changed_rows": 0,
            "late_arriving_rows": 0,
            "volume_ratio": None,
            "volume_spike_detected": False,
            "volume_drop_detected": False,
        }

    changed_df, new_watermark = _apply_event_time_annotations(
        changed_df,
        event_time_column,
        src_state.get("event_time_watermark"),
    )
    late_arriving_rows = int(changed_df.get("is_late_arriving", pd.Series(dtype=bool)).sum())

    ingest_ts = datetime.now(timezone.utc)
    changed_df["ingested_at"] = ingest_ts.isoformat()
    changed_df["source_name"] = source_name

    volume_ratio, volume_spike_detected, volume_drop_detected = _evaluate_volume_change(
        current_rows=int(len(df)),
        previous_rows=int(previous_rows) if previous_rows is not None else None,
        spike_threshold_ratio=spike_threshold_ratio,
        drop_threshold_ratio=drop_threshold_ratio,
    )

    out_path = join_uri(
        bronze_dir,
        f"ingest_year={ingest_ts:%Y}",
        f"ingest_month={ingest_ts:%m}",
        f"ingest_day={ingest_ts:%d}",
        f"{source_name}_{ingest_ts:%Y%m%dT%H%M%S%fZ}.parquet",
    )
    write_parquet(changed_df, out_path)

    state_payload = {
        "last_file_hash": src_hash,
        "last_ingested_at": ingest_ts.isoformat(),
        "last_rows": int(len(df)),
        "last_changed_rows": int(len(changed_df)),
        "last_late_arriving_rows": late_arriving_rows,
        "last_output_path": str(out_path),
        "last_status": "ingested",
        "last_volume_ratio": volume_ratio,
        "last_volume_spike_detected": volume_spike_detected,
        "last_volume_drop_detected": volume_drop_detected,
    }
    if new_watermark:
        state_payload["event_time_watermark"] = new_watermark

    state_store.upsert_source(source_name, state_payload)

    return {
        "source_name": source_name,
        "status": "ingested",
        "rows": int(len(changed_df)),
        "changed_rows": int(len(changed_df)),
        "late_arriving_rows": late_arriving_rows,
        "volume_ratio": volume_ratio,
        "volume_spike_detected": volume_spike_detected,
        "volume_drop_detected": volume_drop_detected,
    }


def run(
    config_path: str,
    data_root: str,
    force_replay: bool = False,
    replay_failed_only: bool = False,
    source_base: str | None = None,
) -> None:
    config = yaml.safe_load(read_text(config_path))

    source_base = source_base or str(Path.cwd())

    bronze_dir = join_uri(data_root, "bronze")
    audit_dir = join_uri(data_root, "audit")
    state_store = StateStore(join_uri(audit_dir, "checkpoints.json"))

    ingest_results: list[dict] = []
    for source in config["sources"]:
        if not source.get("enabled", True):
            ingest_results.append(
                {
                    "source_name": source["source_name"],
                    "status": "disabled",
                    "rows": 0,
                    "changed_rows": 0,
                    "late_arriving_rows": 0,
                    "volume_ratio": None,
                    "volume_spike_detected": False,
                    "volume_drop_detected": False,
                }
            )
            continue

        source_name = source["source_name"]
        src_state = state_store.get_source(source_name)
        if replay_failed_only and src_state.get("last_status") != "failed":
            ingest_results.append(
                {
                    "source_name": source_name,
                    "status": "not_failed",
                    "rows": 0,
                    "changed_rows": 0,
                    "late_arriving_rows": 0,
                    "volume_ratio": None,
                    "volume_spike_detected": False,
                    "volume_drop_detected": False,
                }
            )
            continue

        try:
            result = _ingest_one_source(source, source_base, bronze_dir, state_store, force_replay)
            ingest_results.append(result)
        except Exception as exc:
            state_store.upsert_source(
                source_name,
                {
                    "last_status": "failed",
                    "last_error": str(exc),
                    "last_failed_at": datetime.now(timezone.utc).isoformat(),
                },
            )
            ingest_results.append(
                {
                    "source_name": source_name,
                    "status": "failed",
                    "rows": 0,
                    "changed_rows": 0,
                    "late_arriving_rows": 0,
                    "volume_ratio": None,
                    "volume_spike_detected": False,
                    "volume_drop_detected": False,
                    "error": str(exc),
                }
            )

    total_ingested = sum(item["rows"] for item in ingest_results)
    total_changed = sum(item.get("changed_rows", 0) for item in ingest_results)
    total_late_arriving = sum(item.get("late_arriving_rows", 0) for item in ingest_results)
    total_spike_detected = sum(1 for item in ingest_results if item.get("volume_spike_detected", False))
    total_drop_detected = sum(1 for item in ingest_results if item.get("volume_drop_detected", False))
    emit_metric(join_uri(audit_dir, "metrics.csv"), "bronze_rows_ingested", float(total_ingested))
    emit_metric(join_uri(audit_dir, "metrics.csv"), "bronze_changed_rows", float(total_changed))
    emit_metric(join_uri(audit_dir, "metrics.csv"), "bronze_late_arriving_rows", float(total_late_arriving))
    emit_metric(join_uri(audit_dir, "metrics.csv"), "volume_spike_detected_sources", float(total_spike_detected))
    emit_metric(join_uri(audit_dir, "metrics.csv"), "volume_drop_detected_sources", float(total_drop_detected))

    write_csv(pd.DataFrame(ingest_results), join_uri(audit_dir, "bronze_run_report.csv"))

    volume_report = pd.DataFrame(
        [
            {
                "source_name": item.get("source_name"),
                "status": item.get("status"),
                "volume_ratio": item.get("volume_ratio"),
                "volume_spike_detected": item.get("volume_spike_detected", False),
                "volume_drop_detected": item.get("volume_drop_detected", False),
            }
            for item in ingest_results
        ]
    )
    write_csv(volume_report, join_uri(audit_dir, "volume_report.csv"))

    freshness_df = _build_freshness_report(config, state_store, ingest_results)
    write_csv(freshness_df, join_uri(audit_dir, "freshness_report.csv"))

    missing_updates_count = int(freshness_df["missing_updates"].sum()) if len(freshness_df) else 0
    ingestion_delay_breached_count = int(freshness_df["ingestion_delay_breached"].sum()) if len(freshness_df) else 0
    emit_metric(join_uri(audit_dir, "metrics.csv"), "freshness_missing_updates_sources", float(missing_updates_count))
    emit_metric(
        join_uri(audit_dir, "metrics.csv"),
        "freshness_ingestion_delay_breached_sources",
        float(ingestion_delay_breached_count),
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Bronze ingestion for global power plant datasets")
    parser.add_argument("--config", default="pipelines/configs/sources.yaml")
    parser.add_argument("--data-root", default="artifacts/local")
    parser.add_argument("--source-base", default=".")
    parser.add_argument("--force-replay", action="store_true")
    parser.add_argument("--replay-failed-only", action="store_true")
    args, _ = parser.parse_known_args()
    return args


if __name__ == "__main__":
    args = parse_args()
    run(
        args.config,
        args.data_root,
        force_replay=args.force_replay,
        replay_failed_only=args.replay_failed_only,
        source_base=args.source_base,
    )
