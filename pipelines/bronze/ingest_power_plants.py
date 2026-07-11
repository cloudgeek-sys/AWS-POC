from __future__ import annotations

import argparse
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import yaml

from pipelines.common.io_utils import file_hash, join_uri, read_dataset, read_text, write_csv, write_parquet
from pipelines.common.metrics import emit_local_metric
from pipelines.common.state_store import StateStore


def _ingest_one_source(
    source: dict,
    source_base: str,
    bronze_dir: str,
    state_store: StateStore,
    force_replay: bool,
) -> dict:
    source_name = source["source_name"]
    source_path = join_uri(source_base, source["path"])
    file_format = source["format"]

    src_state = state_store.get_source(source_name)
    src_hash = file_hash(source_path)

    if not force_replay and src_state.get("last_file_hash") == src_hash:
        return {"source_name": source_name, "status": "skipped", "rows": 0}

    df = read_dataset(source_path, file_format)
    ingest_ts = datetime.now(timezone.utc)
    df["ingested_at"] = ingest_ts.isoformat()
    df["source_name"] = source_name

    out_path = join_uri(
        bronze_dir,
        f"ingest_year={ingest_ts:%Y}",
        f"ingest_month={ingest_ts:%m}",
        f"ingest_day={ingest_ts:%d}",
        f"{source_name}.parquet",
    )
    write_parquet(df, out_path)

    state_store.upsert_source(
        source_name,
        {
            "last_file_hash": src_hash,
            "last_ingested_at": ingest_ts.isoformat(),
            "last_rows": int(len(df)),
            "last_output_path": str(out_path),
        },
    )

    return {"source_name": source_name, "status": "ingested", "rows": int(len(df))}


def run(
    config_path: str,
    data_root: str,
    force_replay: bool = False,
    source_base: str | None = None,
) -> None:
    config = yaml.safe_load(read_text(config_path))

    source_base = source_base or str(Path.cwd())

    bronze_dir = join_uri(data_root, "bronze")
    audit_dir = join_uri(data_root, "audit")
    state_store = StateStore(join_uri(audit_dir, "checkpoints.json"))

    ingest_results: list[dict] = []
    for source in config["sources"]:
        result = _ingest_one_source(source, source_base, bronze_dir, state_store, force_replay)
        ingest_results.append(result)

    total_ingested = sum(item["rows"] for item in ingest_results)
    emit_local_metric(join_uri(audit_dir, "metrics.csv"), "bronze_rows_ingested", float(total_ingested))

    write_csv(pd.DataFrame(ingest_results), join_uri(audit_dir, "bronze_run_report.csv"))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Bronze ingestion for global power plant datasets")
    parser.add_argument("--config", default="pipelines/configs/sources.yaml")
    parser.add_argument("--data-root", default="artifacts/local")
    parser.add_argument("--source-base", default=".")
    parser.add_argument("--force-replay", action="store_true")
    args, _ = parser.parse_known_args()
    return args


if __name__ == "__main__":
    args = parse_args()
    run(args.config, args.data_root, force_replay=args.force_replay, source_base=args.source_base)
