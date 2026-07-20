from __future__ import annotations

import argparse
import os
import sys
import tempfile
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from pipelines.bronze.ingest_power_plants import run as bronze_run
from pipelines.gold.build_gold_tables import run as gold_run
from pipelines.silver.transform_power_plants import run as silver_run


def _first_csv_file(directory: Path) -> Path:
    candidates = sorted(p for p in directory.rglob("*.csv") if p.is_file())
    if not candidates:
        raise FileNotFoundError(f"No CSV files found in directory: {directory}")
    return candidates[0]


def _write_runtime_source_config(csv_path: Path, config_path: Path) -> None:
    config = {
        "sources": [
            {
                "source_name": "runtime_power_plants",
                "enabled": True,
                "format": "csv",
                "path": str(csv_path),
                "primary_key": "plant_id",
                "event_time_column": "commissioning_year",
            }
        ]
    }
    config_path.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")


def run(source_dir: Path, incremental_dir: Path, output_dir: Path) -> None:
    repo_root = Path(__file__).resolve().parents[1]
    source_dir = source_dir if source_dir.is_absolute() else (repo_root / source_dir)
    incremental_dir = incremental_dir if incremental_dir.is_absolute() else (repo_root / incremental_dir)
    output_dir = output_dir if output_dir.is_absolute() else (repo_root / output_dir)

    if not source_dir.exists():
        raise FileNotFoundError(f"Source directory not found: {source_dir}")
    if not incremental_dir.exists():
        raise FileNotFoundError(f"Incremental directory not found: {incremental_dir}")

    # CI/local simulation should not require AWS credentials for CloudWatch metrics.
    os.environ["DISABLE_CLOUDWATCH_METRICS"] = "true"

    baseline_csv = _first_csv_file(source_dir)
    incremental_csv = _first_csv_file(incremental_dir)

    with tempfile.TemporaryDirectory(prefix="local-sim-") as temp_dir:
        baseline_config = Path(temp_dir) / "sources_baseline.yaml"
        incremental_config = Path(temp_dir) / "sources_incremental.yaml"
        _write_runtime_source_config(baseline_csv, baseline_config)
        _write_runtime_source_config(incremental_csv, incremental_config)

        bronze_run(
            str(baseline_config),
            output_dir,
            force_replay=False,
            source_base=repo_root,
        )
        silver_run(
            output_dir,
            repo_root / "pipelines" / "schemas" / "power_plants_schema.json",
            baseline_config,
        )
        gold_run(output_dir)

        # Simulate an incremental replay window by ingesting the incremental sample.
        bronze_run(
            str(incremental_config),
            output_dir,
            force_replay=True,
            source_base=repo_root,
        )
        silver_run(
            output_dir,
            repo_root / "pipelines" / "schemas" / "power_plants_schema.json",
            incremental_config,
        )
        gold_run(output_dir)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Local simulation for incremental ingestion and medallion processing")
    parser.add_argument("--source-dir", required=True)
    parser.add_argument("--incremental-dir", required=True)
    parser.add_argument("--output-dir", default="artifacts/local")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    run(Path(args.source_dir), Path(args.incremental_dir), Path(args.output_dir))
