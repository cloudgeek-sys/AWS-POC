from __future__ import annotations

import hashlib
import io
import json
from pathlib import Path
from typing import Any

import boto3
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def is_s3_uri(path: str | Path) -> bool:
    return str(path).startswith("s3://")


def split_s3_uri(uri: str | Path) -> tuple[str, str]:
    value = str(uri)
    without_scheme = value[len("s3://"):]
    bucket, _, key = without_scheme.partition("/")
    return bucket, key


def join_uri(base: str | Path, *parts: str) -> str:
    base_str = str(base).rstrip("/")
    if is_s3_uri(base_str):
        clean_parts = [p.strip("/") for p in parts if p]
        return "/".join([base_str, *clean_parts])
    return str(Path(base_str, *parts))


def list_s3_keys(prefix_uri: str | Path, suffix: str | None = None) -> list[str]:
    bucket, prefix = split_s3_uri(prefix_uri)
    client = boto3.client("s3")
    paginator = client.get_paginator("list_objects_v2")
    keys: list[str] = []
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for item in page.get("Contents", []):
            key = item["Key"]
            if suffix is None or key.endswith(suffix):
                keys.append(f"s3://{bucket}/{key}")
    return keys


def _read_s3_bytes(uri: str | Path) -> bytes:
    bucket, key = split_s3_uri(uri)
    client = boto3.client("s3")
    return client.get_object(Bucket=bucket, Key=key)["Body"].read()


def _write_s3_bytes(uri: str | Path, data: bytes, content_type: str | None = None) -> None:
    bucket, key = split_s3_uri(uri)
    client = boto3.client("s3")
    kwargs: dict[str, Any] = {"Bucket": bucket, "Key": key, "Body": data}
    if content_type:
        kwargs["ContentType"] = content_type
    client.put_object(**kwargs)


def read_dataset(path: str | Path, file_format: str) -> pd.DataFrame:
    if is_s3_uri(path):
        raw = _read_s3_bytes(path)
        if file_format.lower() == "csv":
            return pd.read_csv(io.BytesIO(raw))
        if file_format.lower() == "json":
            return pd.read_json(io.BytesIO(raw))
        if file_format.lower() == "parquet":
            table = pq.read_table(io.BytesIO(raw))
            return table.to_pandas()
        raise ValueError(f"Unsupported format: {file_format}")

    if file_format.lower() == "csv":
        return pd.read_csv(path)
    if file_format.lower() == "json":
        return pd.read_json(path)
    if file_format.lower() == "parquet":
        return pd.read_parquet(path)
    raise ValueError(f"Unsupported format: {file_format}")


def write_parquet(df: pd.DataFrame, path: str | Path) -> None:
    if is_s3_uri(path):
        buffer = io.BytesIO()
        table = pa.Table.from_pandas(df)
        pq.write_table(table, buffer)
        _write_s3_bytes(path, buffer.getvalue(), content_type="application/octet-stream")
        return
    local_path = Path(path)
    ensure_dir(local_path.parent)
    df.to_parquet(local_path, index=False)


def write_json(payload: dict[str, Any], path: str | Path) -> None:
    serialized = json.dumps(payload, indent=2)
    if is_s3_uri(path):
        _write_s3_bytes(path, serialized.encode("utf-8"), content_type="application/json")
        return
    local_path = Path(path)
    ensure_dir(local_path.parent)
    local_path.write_text(serialized, encoding="utf-8")


def read_json(path: str | Path) -> dict[str, Any]:
    if is_s3_uri(path):
        try:
            return json.loads(_read_s3_bytes(path).decode("utf-8"))
        except Exception:
            return {}
    local_path = Path(path)
    if not local_path.exists():
        return {}
    return json.loads(local_path.read_text(encoding="utf-8"))


def read_text(path: str | Path) -> str:
    if is_s3_uri(path):
        return _read_s3_bytes(path).decode("utf-8")
    return Path(path).read_text(encoding="utf-8")


def write_csv(df: pd.DataFrame, path: str | Path) -> None:
    if is_s3_uri(path):
        _write_s3_bytes(path, df.to_csv(index=False).encode("utf-8"), content_type="text/csv")
        return
    local_path = Path(path)
    ensure_dir(local_path.parent)
    df.to_csv(local_path, index=False)


def append_text(path: str | Path, text: str) -> None:
    if is_s3_uri(path):
        try:
            existing = _read_s3_bytes(path).decode("utf-8")
        except Exception:
            existing = ""
        _write_s3_bytes(path, (existing + text).encode("utf-8"), content_type="text/plain")
        return
    local_path = Path(path)
    ensure_dir(local_path.parent)
    with local_path.open("a", encoding="utf-8") as f:
        f.write(text)


def file_hash(path: str | Path) -> str:
    digest = hashlib.sha256()
    if is_s3_uri(path):
        digest.update(_read_s3_bytes(path))
        return digest.hexdigest()

    local_path = Path(path)
    with local_path.open("rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            digest.update(chunk)
    return digest.hexdigest()
