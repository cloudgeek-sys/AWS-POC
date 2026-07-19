from __future__ import annotations

import argparse
import hashlib
from datetime import datetime
from pathlib import Path

import pandas as pd

from pipelines.common.constants import RENEWABLE_FUELS
from pipelines.common.io_utils import ensure_dir, is_s3_uri, join_uri, read_dataset, write_json, write_parquet
from pipelines.common.metrics import emit_metric


def _mask_owner(value: object) -> str:
    if pd.isna(value):
        return "UNKNOWN"
    raw = str(value).strip()
    if raw == "":
        return "UNKNOWN"
    digest = hashlib.sha256(raw.encode("utf-8")).hexdigest()[:10]
    return f"OWNER_{digest}"


def _schema_doc(df: pd.DataFrame, dataset_name: str) -> dict:
    columns = []
    for col in df.columns:
        null_count = int(df[col].isna().sum())
        columns.append(
            {
                "name": col,
                "dtype": str(df[col].dtype),
                "nullable": null_count > 0,
                "null_count": null_count,
            }
        )
    return {
        "dataset": dataset_name,
        "row_count": int(len(df)),
        "column_count": int(len(df.columns)),
        "columns": columns,
    }


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
    dim_plant["owner_masked"] = dim_plant["owner"].apply(_mask_owner)
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

        if "event_month" in df.columns:
            fact_generation_time = (
                df.groupby(["event_year", "event_month"], dropna=False, as_index=False)["estimated_generation_gwh"]
                .sum()
                .rename(
                    columns={
                        "estimated_generation_gwh": "total_generation_gwh",
                        "event_year": "year",
                        "event_month": "month",
                    }
                )
            )
        else:
            fact_generation_time = pd.DataFrame(columns=["year", "month", "total_generation_gwh"])
    else:
        fact_generation = pd.DataFrame(columns=["country", "primary_fuel", "year", "total_generation_gwh"])
        fact_generation_time = pd.DataFrame(columns=["year", "month", "total_generation_gwh"])

    if "continent" in df.columns and "sub_region" in df.columns:
        fact_capacity_geo = (
            df.groupby(["continent", "sub_region"], dropna=False, as_index=False)["capacity_mw"]
            .sum()
            .rename(columns={"capacity_mw": "total_capacity_mw"})
        )
    else:
        fact_capacity_geo = pd.DataFrame(columns=["continent", "sub_region", "total_capacity_mw"])

    gold_dir = join_uri(data_root, "gold")
    if not is_s3_uri(gold_dir):
        ensure_dir(Path(gold_dir))

    write_parquet(dim_plant, join_uri(gold_dir, "dim_plant.parquet"))
    write_parquet(dim_country, join_uri(gold_dir, "dim_country.parquet"))
    write_parquet(dim_fuel, join_uri(gold_dir, "dim_fuel_type.parquet"))
    write_parquet(dim_time, join_uri(gold_dir, "dim_time.parquet"))
    write_parquet(fact_capacity, join_uri(gold_dir, "fact_plant_capacity.parquet"))
    write_parquet(fact_generation, join_uri(gold_dir, "fact_power_generation.parquet"))
    write_parquet(fact_generation_time, join_uri(gold_dir, "fact_power_generation_time.parquet"))
    write_parquet(fact_capacity_geo, join_uri(gold_dir, "fact_capacity_geo.parquet"))

    governance_dir = join_uri(data_root, "audit", "governance")
    schema_documentation = {
        "generated_at": datetime.utcnow().isoformat() + "Z",
        "datasets": [
            _schema_doc(df, "silver.stg_power_plants"),
            _schema_doc(dim_plant, "gold.dim_plant"),
            _schema_doc(dim_country, "gold.dim_country"),
            _schema_doc(dim_fuel, "gold.dim_fuel_type"),
            _schema_doc(dim_time, "gold.dim_time"),
            _schema_doc(fact_capacity, "gold.fact_plant_capacity"),
            _schema_doc(fact_generation, "gold.fact_power_generation"),
            _schema_doc(fact_generation_time, "gold.fact_power_generation_time"),
            _schema_doc(fact_capacity_geo, "gold.fact_capacity_geo"),
        ],
    }
    write_json(schema_documentation, join_uri(governance_dir, "schema_documentation.json"))

    data_lineage = {
        "generated_at": datetime.utcnow().isoformat() + "Z",
        "edges": [
            {
                "from": "bronze.wri_global_power_plants",
                "to": "silver.stg_power_plants",
                "transformation": "canonical_mapping + quality_validation + normalization + upsert",
            },
            {
                "from": "silver.stg_power_plants",
                "to": "gold.dim_plant",
                "transformation": "dimension_projection",
            },
            {
                "from": "silver.stg_power_plants",
                "to": "gold.dim_country",
                "transformation": "distinct_country",
            },
            {
                "from": "silver.stg_power_plants",
                "to": "gold.dim_fuel_type",
                "transformation": "distinct_fuel + renewable_flag",
            },
            {
                "from": "silver.stg_power_plants",
                "to": "gold.dim_time",
                "transformation": "execution_time_dimension",
            },
            {
                "from": "silver.stg_power_plants",
                "to": "gold.fact_plant_capacity",
                "transformation": "aggregate_capacity_by_country_fuel",
            },
            {
                "from": "silver.stg_power_plants",
                "to": "gold.fact_power_generation",
                "transformation": "aggregate_generation_by_country_fuel_year",
            },
            {
                "from": "silver.stg_power_plants",
                "to": "gold.fact_power_generation_time",
                "transformation": "aggregate_generation_by_year_month",
            },
            {
                "from": "silver.stg_power_plants",
                "to": "gold.fact_capacity_geo",
                "transformation": "aggregate_capacity_by_continent_sub_region",
            },
        ],
    }
    write_json(data_lineage, join_uri(governance_dir, "data_lineage.json"))

    aggregation_report = {
        "generated_at": datetime.utcnow().isoformat() + "Z",
        "capacity_aggregation": {
            "applied": True,
            "output_rows": int(len(fact_capacity)),
            "source": "silver.stg_power_plants",
            "group_by": ["country", "primary_fuel"],
        },
        "time_based_aggregation": {
            "applied": True,
            "output_rows": int(len(fact_generation_time)),
            "source": "silver.stg_power_plants",
            "group_by": ["event_year", "event_month"],
        },
        "geo_based_aggregation": {
            "applied": True,
            "output_rows": int(len(fact_capacity_geo)),
            "source": "silver.stg_power_plants",
            "group_by": ["continent", "sub_region"],
        },
    }
    write_json(aggregation_report, join_uri(governance_dir, "transformation_aggregation_report.json"))

    renewable_total = fact_capacity["renewable_capacity_mw"].sum()
    total_capacity = fact_capacity["total_capacity_mw"].sum()
    renewable_ratio = float(renewable_total / total_capacity) if total_capacity else 0.0
    average_plant_capacity = float(dim_plant["capacity_mw"].mean()) if len(dim_plant) else 0.0

    country_fuel_distribution = (
        fact_generation.groupby(["country", "primary_fuel"], dropna=False, as_index=False)["total_generation_gwh"]
        .sum()
        .sort_values(["country", "primary_fuel"])
    )
    annual_generation_trends = (
        fact_generation.groupby(["year"], dropna=False, as_index=False)["total_generation_gwh"]
        .sum()
        .sort_values(["year"])
    )

    mandatory_kpi_report = pd.DataFrame(
        [
            {
                "generated_at": datetime.utcnow().isoformat() + "Z",
                "total_generation_capacity_mw": float(total_capacity),
                "renewable_energy_ratio": float(renewable_ratio),
                "average_plant_capacity_mw": float(average_plant_capacity),
                "country_wise_fuel_distribution_rows": int(len(country_fuel_distribution)),
                "annual_generation_trends_rows": int(len(annual_generation_trends)),
            }
        ]
    )

    audit_dir = join_uri(data_root, "audit")
    write_parquet(country_fuel_distribution, join_uri(gold_dir, "country_fuel_distribution.parquet"))
    write_parquet(annual_generation_trends, join_uri(gold_dir, "annual_generation_trends.parquet"))
    write_json(mandatory_kpi_report.to_dict(orient="records")[0], join_uri(audit_dir, "mandatory_kpi_report.json"))
    emit_metric(join_uri(audit_dir, "metrics.csv"), "gold_rows_fact_capacity", float(len(fact_capacity)))
    emit_metric(join_uri(audit_dir, "metrics.csv"), "renewable_energy_ratio", renewable_ratio)
    emit_metric(join_uri(audit_dir, "metrics.csv"), "gold_capacity_aggregation_rows", float(len(fact_capacity)))
    emit_metric(join_uri(audit_dir, "metrics.csv"), "gold_time_aggregation_rows", float(len(fact_generation_time)))
    emit_metric(join_uri(audit_dir, "metrics.csv"), "gold_geo_aggregation_rows", float(len(fact_capacity_geo)))
    emit_metric(join_uri(audit_dir, "metrics.csv"), "gold_total_generation_capacity_mw", float(total_capacity))
    emit_metric(join_uri(audit_dir, "metrics.csv"), "gold_average_plant_capacity_mw", float(average_plant_capacity))
    emit_metric(
        join_uri(audit_dir, "metrics.csv"),
        "gold_country_wise_fuel_distribution_rows",
        float(len(country_fuel_distribution)),
    )
    emit_metric(
        join_uri(audit_dir, "metrics.csv"),
        "gold_annual_generation_trends_rows",
        float(len(annual_generation_trends)),
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build Gold facts and dimensions")
    parser.add_argument("--data-root", default="artifacts/local")
    args, _ = parser.parse_known_args()
    return args


if __name__ == "__main__":
    args = parse_args()
    run(args.data_root)
