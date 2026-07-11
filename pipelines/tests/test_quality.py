import pandas as pd

from pipelines.common.quality import split_malformed_records


def test_split_malformed_records_filters_invalid_rows() -> None:
    df = pd.DataFrame(
        [
            {"plant_id": "P1", "plant_name": "A", "country": "X", "primary_fuel": "Coal", "capacity_mw": 100.0},
            {"plant_id": "P2", "plant_name": None, "country": "Y", "primary_fuel": "Gas", "capacity_mw": 200.0},
            {"plant_id": "P3", "plant_name": "C", "country": "Z", "primary_fuel": "Solar", "capacity_mw": -1.0},
        ]
    )

    valid_df, malformed_df = split_malformed_records(
        df,
        required_columns=["plant_id", "plant_name", "country", "primary_fuel", "capacity_mw"],
        range_rules={"capacity_mw": {"min": 0.0001, "max": 1000000}},
    )

    assert len(valid_df) == 1
    assert len(malformed_df) == 2
