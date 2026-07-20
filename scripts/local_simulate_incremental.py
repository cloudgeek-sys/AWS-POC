from __future__ import annotations

import argparse
import csv
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


def _write_fallback_fixture(csv_path: Path, rows: list[dict]) -> None:
    fieldnames = [
        "plant_id",
        "plant_name",
        "country",
        "primary_fuel",
        "capacity_mw",
        "commissioning_year",
        "latitude",
        "longitude",
        "estimated_generation_gwh",
        "owner",
        "last_updated_at",
    ]
    with csv_path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def _build_fallback_inputs(temp_dir: Path) -> tuple[Path, Path]:
    baseline_csv = temp_dir / "fallback_baseline.csv"
    incremental_csv = temp_dir / "fallback_incremental.csv"

    baseline_rows = [
        {
            "plant_id": "SIM-001",
            "plant_name": "Alpha Solar One",
            "country": "India",
            "primary_fuel": "Solar",
            "capacity_mw": "120",
            "commissioning_year": "2018",
            "latitude": "23.5937",
            "longitude": "78.9629",
            "estimated_generation_gwh": "210",
            "owner": "Sample Utility",
            "last_updated_at": "2026-01-01T00:00:00+00:00",
        },
        {
            "plant_id": "SIM-002",
            "plant_name": "Beta Hydro Station",
            "country": "Brazil",
            "primary_fuel": "Hydro",
            "capacity_mw": "310",
            "commissioning_year": "2012",
            "latitude": "-14.2350",
            "longitude": "-51.9253",
            "estimated_generation_gwh": "980",
            "owner": "Grid Operator",
            "last_updated_at": "2026-01-01T00:00:00+00:00",
        },
    ]

    incremental_rows = [
        {
            "plant_id": "SIM-001",
            "plant_name": "Alpha Solar One",
            "country": "India",
            "primary_fuel": "Solar",
            "capacity_mw": "125",
            "commissioning_year": "2018",
            "latitude": "23.5937",
            "longitude": "78.9629",
            "estimated_generation_gwh": "225",
            "owner": "Sample Utility",
            "last_updated_at": "2026-02-01T00:00:00+00:00",
        },
        {
            "plant_id": "SIM-003",
            "plant_name": "Gamma Wind Farm",
            "country": "United States",
            "primary_fuel": "Wind",
            "capacity_mw": "200",
            "commissioning_year": "2020",
            "latitude": "37.0902",
            "longitude": "-95.7129",
            "estimated_generation_gwh": "450",
            "owner": "Regional Energy",
            "last_updated_at": "2026-02-01T00:00:00+00:00",
        },
    ]

    _write_fallback_fixture(baseline_csv, baseline_rows)
    _write_fallback_fixture(incremental_csv, incremental_rows)
    return baseline_csv, incremental_csv


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

    with tempfile.TemporaryDirectory(prefix="local-sim-") as temp_dir:
        temp_path = Path(temp_dir)
        try:
            baseline_csv = _first_csv_file(source_dir)
            incremental_csv = _first_csv_file(incremental_dir)
        except FileNotFoundError:
            baseline_csv, incremental_csv = _build_fallback_inputs(temp_path)

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
