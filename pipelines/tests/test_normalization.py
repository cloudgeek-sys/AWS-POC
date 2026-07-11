from pipelines.common.normalization import normalize_country, normalize_fuel


def test_country_normalization_aliases() -> None:
    assert normalize_country("usa") == "United States"
    assert normalize_country("UK") == "United Kingdom"


def test_fuel_normalization_aliases() -> None:
    assert normalize_fuel("natural gas") == "Gas"
    assert normalize_fuel("hydroelectric") == "Hydro"
