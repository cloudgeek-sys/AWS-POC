from __future__ import annotations

import argparse
from pathlib import Path

import duckdb
import pandas as pd


def _load_table(con: duckdb.DuckDBPyConnection, parquet_path: Path, schema: str, table: str) -> None:
    if not parquet_path.exists():
        raise FileNotFoundError(f"Missing parquet file for {schema}.{table}: {parquet_path}")

    df = pd.read_parquet(parquet_path)
    con.execute(f"CREATE SCHEMA IF NOT EXISTS {schema}")
    con.register("tmp_df", df)
    con.execute(f"CREATE OR REPLACE TABLE {schema}.{table} AS SELECT * FROM tmp_df")
    con.unregister("tmp_df")


def run(artifacts_root: Path, db_path: Path) -> None:
    con = duckdb.connect(str(db_path))
    try:
        _load_table(
            con,
            artifacts_root / "silver" / "stg_power_plants.parquet",
            "gppa_silver",
            "stg_power_plants",
        )
        _load_table(
            con,
            artifacts_root / "gold" / "fact_power_generation.parquet",
            "gppa_gold",
            "fact_power_generation",
        )
        _load_table(
            con,
            artifacts_root / "gold" / "fact_plant_capacity.parquet",
            "gppa_gold",
            "fact_plant_capacity",
        )
    finally:
        con.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prepare DuckDB fixtures for dbt CI")
    parser.add_argument("--artifacts-root", default="artifacts/local")
    parser.add_argument("--db-path", default="analytics/dbt/gppa_ci.duckdb")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    run(Path(args.artifacts_root), Path(args.db_path))
