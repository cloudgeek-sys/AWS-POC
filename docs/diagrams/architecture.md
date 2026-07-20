# Architecture and Data Flow

## Design principles

- Production-first architecture with modular IaC and CI/CD
- Medallion model (Bronze/Silver/Gold)
- Kimball dimensional marts for BI consumption in QuickSight
- Idempotent and replay-safe ingestion semantics
- Observability-first (data quality + freshness + latency)

## Deployed baseline (current)

- AWS Account: `371170753734`
- AWS Region: `us-east-1`
- Data lake bucket: `gppa-main-lake-platform-20260710212811`
- Step Functions ARN: `arn:aws:states:us-east-1:371170753734:stateMachine:gppa-main-power-pipeline`
- Athena workgroup: `gppa-main-wg`
- QuickSight Athena data source ARN: `arn:aws:quicksight:us-east-1:371170753734:datasource/gppa_main_athena`

Active source scope (mandatory current baseline):

- `global_power_plants_synthetic_records_v2` (`datasets/global_power_plants_synthetic_records_v2.csv`)
- `global_power_plants_synthetic_records` (`datasets/global_power_plants_synthetic.csv`)

## Logical architecture

```mermaid
flowchart LR
  A[Configured CSV Sources\nTwo synthetic datasets] --> B[Ingestion Jobs\nAWS Glue Python]
    B --> C[S3 Bronze\nIncremental parquet snapshots]
    C --> D[Silver Transform\nStandardize + DQ + Dedupe]
    D --> E[S3 Silver\nConformed Parquet]
    E --> F[Gold Build\nFacts + Dimensions]
  F --> G[S3 Gold / Athena]
  G --> N[Visualization Build\nPNG + Manifest]

    B --> I[Run Metadata\nS3 audit + checkpoints]
    D --> J[Quarantine\nMalformed records]
    B --> K[CloudWatch Metrics]
    D --> K
    F --> K
  N --> K
  K --> L[CloudWatch Alarms]

    M[Step Functions] --> B
    M --> D
    M --> F
  M --> N

  G --> Q[Athena Views]
  Q --> R[QuickSight Dashboards]
```

## Mandatory process alignment

The deployed orchestration and BI model must satisfy this mandatory sequence:

1. Bronze to Silver: perform data quality validation in a single consolidated Silver stage
2. Silver to Gold: build validated analytical facts and dimensions
3. Query and KPI creation: execute Athena KPI queries on Gold views
4. Dashboards and reports: publish QuickSight datasets/dashboards and visualization artifacts
5. Alerts: publish quick insights through SNS and email subscribers

Single-stage DQ design:

- DQ checks are consolidated in the Silver transform stage (`pipelines/silver/transform_power_plants.py`)
- Checks include schema validation/drift, null checks, range validation, duplicate prevention, and idempotent upsert validation
- Malformed records are persisted separately in quarantine output (`quarantine/stg_power_plants_malformed.parquet`)

The architecture diagram (`docs/diagrams/architecture.mmd`) and Step Functions definitions are aligned to this flow.

## Physical AWS components

- Amazon S3 data lake buckets/prefixes:
  - bucket: gppa-main-lake-platform-20260710212811
  - bronze/
  - silver/
  - gold/
  - quarantine/
  - audit/
- AWS Glue Catalog databases:
  - gppa_main_bronze
  - gppa_main_silver
  - gppa_main_gold
- AWS Glue jobs:
  - gppa-main-bronze-ingest-power-plants
  - gppa-main-silver-transform-power-plants
  - gppa-main-gold-build-power-analytics
  - gppa-main-visualizations-build
- AWS Glue crawlers:
  - gppa-main-bronze-crawler
  - gppa-main-silver-crawler
  - gppa-main-gold-crawler
- AWS Step Functions:
  - arn:aws:states:us-east-1:371170753734:stateMachine:gppa-main-power-pipeline
- Amazon Athena:
  - workgroup: gppa-main-wg
- Amazon QuickSight:
  - data source: arn:aws:quicksight:us-east-1:371170753734:datasource/gppa_main_athena
- Amazon CloudWatch:
  - metrics, alarms, and logs

## Data model overview

Dimensions:

- DimPlant
- DimCountry
- DimFuelType
- DimTime

Facts:

- FactPlantCapacity
- FactPowerGeneration
- FactPowerGenerationTime
- FactCapacityGeo

## Partition strategy

Bronze:

- ingest_year=YYYY/ingest_month=MM/ingest_day=DD/

Silver:

- single output object: silver/stg_power_plants.parquet

Gold:

- curated parquet objects under gold/ (dimensions, facts, KPI-support outputs)

## Late-arriving and replay strategy

- Event-time column retained from source when available
- Watermark-based incremental window to include late arrivals
- Checkpoint table stores last successful event timestamp and file hashes
- Replay mode reprocesses a bounded date window idempotently

## BI scope

- BI scope is QuickSight-only for active delivery
- Dashboard evidence is maintained as PDFs under dashboards/
