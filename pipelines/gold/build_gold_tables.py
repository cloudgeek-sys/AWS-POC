from __future__ import annotations

import argparse
from datetime import datetime
from pathlib import Path

import pandas as pd

from pipelines.common.constants import RENEWABLE_FUELS
from pipelines.common.io_utils import ensure_dir, is_s3_uri, join_uri, read_dataset, write_parquet
from pipelines.common.metrics import emit_local_metric


def run(data_root: str) -> None:
    silver_file = join_uri(data_root, "silver", "stg_power_plants.parquet")

    df = read_dataset(silver_file, "parquet")

    dim_plant = df[[
        "plant_id",
        "plant_name",
        "country",
        "capacity_mw",
        "primary_fuel",
        "commissioning_year",
        "latitude",
        "longitude",
        "owner",
    ]].copy()
    dim_plant["owner_masked"] = dim_plant["owner"].astype(str).str[:3] + "***"
    dim_plant = dim_plant.drop(columns=["owner"], errors="ignore")

    dim_country = df[["country"]].drop_duplicates().reset_index(drop=True)
    dim_country["country_id"] = dim_country.index + 1

    dim_fuel = df[["primary_fuel"]].drop_duplicates().reset_index(drop=True)
    dim_fuel["fuel_type_id"] = dim_fuel.index + 1
    dim_fuel["is_renewable"] = dim_fuel["primary_fuel"].isin(RENEWABLE_FUELS)

    now = datetime.utcnow()
    dim_time = pd.DataFrame(
        [{"year": int(now.year), "month": int(now.month), "day": int(now.day), "date": now.date().isoformat()}]
    )

    fact_capacity = (
        df.groupby(["country", "primary_fuel"], dropna=False, as_index=False)["capacity_mw"].sum()
        .rename(columns={"capacity_mw": "total_capacity_mw"})
    )
    fact_capacity["renewable_capacity_mw"] = fact_capacity.apply(
        lambda r: r["total_capacity_mw"] if r["primary_fuel"] in RENEWABLE_FUELS else 0,
        axis=1,
    )

    if "estimated_generation_gwh" in df.columns:
        fact_generation = (
            df.groupby(["country", "primary_fuel", "event_year"], dropna=False, as_index=False)["estimated_generation_gwh"]
            .sum()
            .rename(columns={"estimated_generation_gwh": "total_generation_gwh", "event_year": "year"})
        )
    else:
        fact_generation = pd.DataFrame(columns=["country", "primary_fuel", "year", "total_generation_gwh"])

    gold_dir = join_uri(data_root, "gold")
    if not is_s3_uri(gold_dir):
        ensure_dir(Path(gold_dir))

    write_parquet(dim_plant, join_uri(gold_dir, "dim_plant.parquet"))
    write_parquet(dim_country, join_uri(gold_dir, "dim_country.parquet"))
    write_parquet(dim_fuel, join_uri(gold_dir, "dim_fuel_type.parquet"))
    write_parquet(dim_time, join_uri(gold_dir, "dim_time.parquet"))
    write_parquet(fact_capacity, join_uri(gold_dir, "fact_plant_capacity.parquet"))
    write_parquet(fact_generation, join_uri(gold_dir, "fact_power_generation.parquet"))

    renewable_total = fact_capacity["renewable_capacity_mw"].sum()
    total_capacity = fact_capacity["total_capacity_mw"].sum()
    renewable_ratio = float(renewable_total / total_capacity) if total_capacity else 0.0

    audit_dir = join_uri(data_root, "audit")
    emit_local_metric(join_uri(audit_dir, "metrics.csv"), "gold_rows_fact_capacity", float(len(fact_capacity)))
    emit_local_metric(join_uri(audit_dir, "metrics.csv"), "renewable_energy_ratio", renewable_ratio)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build Gold facts and dimensions")
    parser.add_argument("--data-root", default="artifacts/local")
    args, _ = parser.parse_known_args()
    return args


if __name__ == "__main__":
    args = parse_args()
    run(args.data_root)
