# Global Power Plant Analytics Pipeline on AWS

Production-style, cost-aware, medallion lakehouse pipeline for global power plant analytics.

## 1. What this project delivers

- Metadata-driven ingestion for CSV, JSON, Parquet, and API-like payloads
- Incremental processing with idempotency and replay windows
- Bronze, Silver, Gold data architecture on Amazon S3 + Athena/Redshift-ready models
- Data quality checks (schema, nulls, ranges, duplicates, freshness, volume)
- Orchestration with AWS Step Functions
- Monitoring with CloudWatch metrics and alarms
- Terraform-based infrastructure with environment isolation (dev/qa/prod)
- CI/CD with GitHub Actions for validation and deployment

## 2. High-level architecture

- Bronze: immutable raw files partitioned by ingest date
- Silver: standardized, deduplicated, conformed records
- Gold: dimensional and fact tables for BI and operations

See docs:
- docs/architecture.md
- docs/adrs/0001-lakehouse-medallion.md
- docs/runbooks/operations.md

## 3. Repository structure

- infra/terraform: IaC modules and environment stacks
- pipelines: ingestion, transformation, quality, and tests
- orchestration/step_functions: state machine definitions
- analytics/sql: analytical views and marts
- dashboards: BI definitions and KPI mapping
- samples: small synthetic sample datasets and incremental updates

## 4. Quick start (local)

1. Create virtual environment and install dependencies:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r pipelines/requirements.txt
```

2. Run local simulation (no AWS required):

```bash
python scripts/local_simulate_incremental.py \
  --source-dir samples/raw/power_plants \
  --incremental-dir samples/incremental_updates \
  --output-dir artifacts/local
```

3. Run tests:

```bash
pytest pipelines/tests -q
```

## 5. Deploy infrastructure (dev)

```bash
cd infra/terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

## 5.1 Upload Glue job code (one command)

After Terraform apply, upload pipeline scripts to the S3 code prefix expected by Glue jobs:

```bash
scripts/upload_glue_code.sh --env-dir infra/terraform/environments/dev
```

Or provide bucket directly:

```bash
scripts/upload_glue_code.sh --bucket <your-lake-bucket>
```

## 5.2 CI/CD deploy secrets

For `.github/workflows/deploy-dev.yml`, configure these repository secrets:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`

## 6. Processing flow

1. Ingestion (Bronze): append-only raw ingest with checkpoint/state.
2. Silver transform: normalize country/fuel, enforce schema, dedupe, quarantine bad rows.
3. Gold build: dimensional models + facts + aggregates for dashboard workloads.
4. Monitoring: push custom quality/freshness metrics to CloudWatch.

## 7. Cost optimization defaults

- Single S3 data lake bucket with prefixes and lifecycle policies
- Athena pay-per-query for analytics prototyping
- Glue jobs with minimal workers in dev
- Optional Redshift Serverless only when needed
- Scheduled pipeline cadence with replay controls

## 8. Security and governance

- IAM least-privilege roles by persona (engineer, analyst, dashboard consumer)
- Encryption at rest (S3 SSE-S3/KMS configurable)
- Data catalog metadata and schema versioning
- Lineage and run metadata in audit prefixes

## 9. Assumptions

- Public datasets; owner/operator fields are masked in curated layers
- Incremental feeds simulated monthly/yearly if live APIs unavailable
- Event time is preserved with late-arrival handling and watermark windows

## 10. Next extension points

- Add Glue Data Quality or Great Expectations in pipeline runtime
- Add Iceberg table format for ACID upserts
- Add QuickSight dashboards bound to Gold views
- Add Redshift data sharing for multi-team analytics
