from __future__ import annotations

import argparse
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from pipelines.bronze.ingest_power_plants import run as bronze_run
from pipelines.gold.build_gold_tables import run as gold_run
from pipelines.silver.transform_power_plants import run as silver_run


def run(source_dir: Path, incremental_dir: Path, output_dir: Path) -> None:
    repo_root = Path(__file__).resolve().parents[1]
    source_dir = source_dir if source_dir.is_absolute() else (repo_root / source_dir)
    incremental_dir = incremental_dir if incremental_dir.is_absolute() else (repo_root / incremental_dir)
    output_dir = output_dir if output_dir.is_absolute() else (repo_root / output_dir)

    if not source_dir.exists():
        raise FileNotFoundError(f"Source directory not found: {source_dir}")
    if not incremental_dir.exists():
        raise FileNotFoundError(f"Incremental directory not found: {incremental_dir}")

    bronze_run(
        repo_root / "pipelines" / "configs" / "sources.yaml",
        output_dir,
        force_replay=False,
        source_base=repo_root,
    )
    silver_run(output_dir, repo_root / "pipelines" / "schemas" / "power_plants_schema.json")
    gold_run(output_dir)

    # Simulate an incremental replay window by forcing re-ingestion.
    bronze_run(
        repo_root / "pipelines" / "configs" / "sources.yaml",
        output_dir,
        force_replay=True,
        source_base=repo_root,
    )
    silver_run(output_dir, repo_root / "pipelines" / "schemas" / "power_plants_schema.json")
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
