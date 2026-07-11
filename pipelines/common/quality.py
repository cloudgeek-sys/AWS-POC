from __future__ import annotations

import json
from pathlib import Path

import pandas as pd

from pipelines.common.io_utils import read_json


def load_schema(schema_path: Path) -> dict:
    return read_json(schema_path)


def validate_required_columns(df: pd.DataFrame, required_columns: list[str]) -> list[str]:
    return [col for col in required_columns if col not in df.columns]


def validate_nulls(df: pd.DataFrame, required_columns: list[str]) -> dict[str, int]:
    issues: dict[str, int] = {}
    for col in required_columns:
        if col in df.columns:
            count = int(df[col].isna().sum())
            if count > 0:
                issues[col] = count
    return issues


def validate_ranges(df: pd.DataFrame, range_rules: dict) -> dict[str, int]:
    issues: dict[str, int] = {}
    for col, bounds in range_rules.items():
        if col not in df.columns:
            continue
        invalid = df[col].notna() & ((df[col] < bounds["min"]) | (df[col] > bounds["max"]))
        count = int(invalid.sum())
        if count > 0:
            issues[col] = count
    return issues


def split_malformed_records(
    df: pd.DataFrame,
    required_columns: list[str],
    range_rules: dict
) -> tuple[pd.DataFrame, pd.DataFrame]:
    valid_mask = pd.Series(True, index=df.index)

    for col in required_columns:
        if col in df.columns:
            valid_mask &= df[col].notna()

    for col, bounds in range_rules.items():
        if col in df.columns:
            valid_mask &= (~df[col].notna()) | ((df[col] >= bounds["min"]) & (df[col] <= bounds["max"]))

    return df[valid_mask].copy(), df[~valid_mask].copy()
