from __future__ import annotations

import argparse
import io
import json
from pathlib import Path

import boto3
import matplotlib
import matplotlib.pyplot as plt
import pandas as pd

from pipelines.common.io_utils import is_s3_uri, join_uri, read_dataset
from pipelines.common.metrics import emit_metric

matplotlib.use("Agg")


def _save_plot(fig: plt.Figure, output_path: str) -> None:
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=150, bbox_inches="tight")
    plt.close(fig)
    data = buf.getvalue()

    if is_s3_uri(output_path):
        bucket_key = output_path[len("s3://") :]
        bucket, _, key = bucket_key.partition("/")
        boto3.client("s3").put_object(Bucket=bucket, Key=key, Body=data, ContentType="image/png")
        return

    out = Path(output_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)


def _write_manifest(output_path: str, payload: dict) -> None:
    body = json.dumps(payload, indent=2).encode("utf-8")
    if is_s3_uri(output_path):
        bucket_key = output_path[len("s3://") :]
        bucket, _, key = bucket_key.partition("/")
        boto3.client("s3").put_object(Bucket=bucket, Key=key, Body=body, ContentType="application/json")
        return

    out = Path(output_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(body)


def run(data_root: str) -> None:
    gold_dir = join_uri(data_root, "gold")
    viz_dir = join_uri(data_root, "visualizations")

    fact_capacity = read_dataset(join_uri(gold_dir, "fact_plant_capacity.parquet"), "parquet")
    fact_generation = read_dataset(join_uri(gold_dir, "fact_power_generation.parquet"), "parquet")

    generated: list[str] = []

    top_country = (
        fact_capacity.groupby("country", dropna=False, as_index=False)["total_capacity_mw"]
        .sum()
        .sort_values("total_capacity_mw", ascending=False)
        .head(10)
    )
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.bar(top_country["country"].astype(str), top_country["total_capacity_mw"])
    ax.set_title("Top Countries by Installed Capacity (MW)")
    ax.set_ylabel("Capacity (MW)")
    ax.set_xlabel("Country")
    ax.tick_params(axis="x", rotation=45)
    out1 = join_uri(viz_dir, "capacity_by_country.png")
    _save_plot(fig, out1)
    generated.append(out1)

    fuel_mix = (
        fact_capacity.groupby("primary_fuel", dropna=False, as_index=False)["total_capacity_mw"]
        .sum()
        .sort_values("total_capacity_mw", ascending=False)
        .head(10)
    )
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.bar(fuel_mix["primary_fuel"].astype(str), fuel_mix["total_capacity_mw"])
    ax.set_title("Fuel Mix by Installed Capacity (Top 10)")
    ax.set_ylabel("Capacity (MW)")
    ax.set_xlabel("Fuel Type")
    ax.tick_params(axis="x", rotation=45)
    out2 = join_uri(viz_dir, "fuel_mix_capacity.png")
    _save_plot(fig, out2)
    generated.append(out2)

    if not fact_generation.empty and "year" in fact_generation.columns:
        gen_trend = (
            fact_generation.groupby("year", dropna=False, as_index=False)["total_generation_gwh"]
            .sum()
            .sort_values("year")
        )
        fig, ax = plt.subplots(figsize=(10, 5))
        ax.plot(gen_trend["year"], gen_trend["total_generation_gwh"], marker="o")
        ax.set_title("Total Estimated Generation Trend")
        ax.set_ylabel("Generation (GWh)")
        ax.set_xlabel("Year")
        out3 = join_uri(viz_dir, "generation_trend.png")
        _save_plot(fig, out3)
        generated.append(out3)

    manifest = {
        "visualizations": generated,
        "count": len(generated),
    }
    _write_manifest(join_uri(viz_dir, "manifest.json"), manifest)

    emit_metric(join_uri(data_root, "audit", "metrics.csv"), "visualizations_generated", float(len(generated)))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build automated visualization artifacts from Gold tables")
    parser.add_argument("--data-root", default="artifacts/local")
    args, _ = parser.parse_known_args()
    return args


if __name__ == "__main__":
    args = parse_args()
    run(args.data_root)
