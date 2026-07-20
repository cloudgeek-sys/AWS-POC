from __future__ import annotations

import re

import pandas as pd

from pipelines.common.constants import COUNTRY_NORMALIZATION, FUEL_NORMALIZATION


INVALID_TEXT_TOKENS = {
    "",
    "?",
    "unknown",
    "unk",
    "na",
    "n/a",
    "null",
    "none",
    "0",
    "-",
    "--",
}


def _clean_text(value: str) -> str:
    return re.sub(r"\s+", " ", str(value).strip().lower())


def normalize_country(country: str) -> str:
    if pd.isna(country):
        return country
    cleaned = _clean_text(country)
    if cleaned in INVALID_TEXT_TOKENS:
        return pd.NA
    return COUNTRY_NORMALIZATION.get(cleaned, str(country).strip().title())


def normalize_fuel(fuel: str) -> str:
    if pd.isna(fuel):
        return fuel
    cleaned = _clean_text(fuel)
    if cleaned in INVALID_TEXT_TOKENS:
        return pd.NA
    return FUEL_NORMALIZATION.get(cleaned, str(fuel).strip().title())
