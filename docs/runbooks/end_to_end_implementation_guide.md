# Global Power Plant Analytics Pipeline: End-to-End Implementation Guide

## 1. Purpose of this guide

This document is a complete, explainable implementation playbook for deploying and operating the Global Power Plant Analytics Pipeline on AWS.

Use this guide to:

- Deploy the platform from scratch
- Validate each stage before moving forward
- Explain architecture and engineering decisions to stakeholders
- Operate and troubleshoot the pipeline in a production-style workflow

---

## 2. What you are implementing

You are implementing a medallion architecture with AWS-native orchestration and analytics:

- Bronze layer: immutable raw ingestion on S3
- Silver layer: standardized, validated, deduplicated data on S3
- Gold layer: analytics-ready facts and dimensions on S3
- Orchestration: AWS Step Functions invoking Glue jobs
- Query/BI: Athena + dashboard-ready SQL models
- Quality/observability: audit artifacts + CloudWatch alarms
- DevOps: Terraform + GitHub Actions

Code and infrastructure are already scaffolded in this repository.

---

## 3. Prerequisites

## 3.1 Local tooling

Install and verify:

- Python 3.10+
- Terraform 1.6+
- AWS CLI v2
- dbt-core and dbt-duckdb (for local contract validation)

## 3.2 AWS account prerequisites

- Active AWS account with permissions for S3, IAM, Glue, Step Functions, CloudWatch, Athena
- Access key / secret key available for local CLI and CI
- Chosen AWS region (example: us-east-1)

## 3.3 GitHub repository secrets (for CI/CD)

Set these repo secrets before running deployment workflows:

- AWS_ACCESS_KEY_ID
- AWS_SECRET_ACCESS_KEY
- AWS_REGION

---

## 4. Repository orientation (what each area does)

- infra/terraform: IaC modules and environment stacks (dev/qa/prod)
- pipelines: Python jobs for Bronze/Silver/Gold and shared quality logic
- orchestration/step_functions: ASL pipeline definition
- analytics/sql: BI and monitoring views
- analytics/dbt: data contracts and model-level tests
- dashboards: KPI mapping and dataset contracts
- scripts: local simulation, dbt fixture prep, Glue code upload
- docs: architecture and operations documentation

---

## 5. Step-by-step implementation

## Step 1: Create local Python environment

Why: isolate dependencies and ensure repeatable execution.

Commands:

```bash
cd /Users/user/AWS-POC
python3 -m venv .venv
source .venv/bin/activate
pip install -r pipelines/requirements.txt
```

Success criteria:

- No dependency install errors
- You can run pytest from this shell

---

## Step 2: Validate pipeline logic locally

Why: prove core ingestion/transform/modeling logic before cloud deployment.

Commands:

```bash
pytest -q
python scripts/local_simulate_incremental.py \
  --source-dir samples/raw/power_plants \
  --incremental-dir samples/incremental_updates \
  --output-dir artifacts/local
```

What this proves:

- Bronze ingestion is idempotent and checkpointed
- Silver applies normalization, quality filtering, and dedupe
- Gold generates dimensions and facts
- Quarantine and audit artifacts are emitted

Success criteria:

- Tests pass
- Artifacts appear under artifacts/local/bronze, silver, gold, quarantine, audit

---

## Step 3: Validate dbt analytics contracts locally

Why: ensure analytics layer and schema contracts are trustworthy before BI integration.

Commands:

```bash
pip install dbt-core==1.8.8 dbt-duckdb==1.8.2 duckdb==1.1.3
python scripts/dbt_prepare_duckdb.py \
  --artifacts-root artifacts/local \
  --db-path analytics/dbt/gppa_ci.duckdb

cd analytics/dbt
cp profiles.yml.ci profiles.yml
DBT_PROFILES_DIR=. dbt run --target ci
DBT_PROFILES_DIR=. dbt test --target ci
cd ../..
```

What this proves:

- dbt models compile and run from current source mappings
- Contract tests (not_null, unique) pass for staging and marts

Success criteria:

- dbt run returns PASS
- dbt test returns PASS

---

## Step 4: Configure Terraform variables for each environment

Why: establish environment-specific parameters and globally unique bucket names.

Files to prepare:

- infra/terraform/environments/dev/terraform.tfvars
- infra/terraform/environments/qa/terraform.tfvars
- infra/terraform/environments/prod/terraform.tfvars

Start from examples:

- infra/terraform/environments/dev/terraform.tfvars.example
- infra/terraform/environments/qa/terraform.tfvars.example
- infra/terraform/environments/prod/terraform.tfvars.example

Minimum values to set:

- aws_region
- project_name
- environment
- data_lake_bucket_suffix (must be globally unique)
- glue_job_worker_count
- schedule_expression

Explanation tip:

Use low Glue worker count in dev to control cost, then tune in qa/prod.

---

## Step 5: Deploy DEV infrastructure with Terraform

Why: provision all AWS runtime components for the pipeline.

Commands:

```bash
cd infra/terraform/environments/dev
terraform init
terraform plan
terraform apply
cd ../../../..
```

What gets provisioned:

- S3 lake bucket and lifecycle policy
- IAM roles/policies for Glue and Step Functions
- Glue catalog databases and three Glue jobs
- Athena workgroup
- Step Functions state machine
- CloudWatch alarms

Success criteria:

- Terraform apply completes with no errors
- Outputs include data_lake_bucket and step_function_arn

---

## Step 6: Upload Glue code to S3

Why: Glue jobs reference script locations in S3, so local code must be synced.

Command (recommended):

```bash
scripts/upload_glue_code.sh --env-dir infra/terraform/environments/dev
```

Alternative command:

```bash
scripts/upload_glue_code.sh --bucket <your-lake-bucket>
```

What this does:

- Syncs pipelines/ to s3://<bucket>/code/pipelines
- Excludes tests and cache artifacts

Success criteria:

- Script exits successfully
- Expected scripts exist under S3 code prefix

---

## Step 7: Execute orchestration on AWS

Why: run end-to-end workflow in cloud exactly as production would.

Option A: AWS Console

- Open Step Functions
- Start execution for the pipeline state machine

Option B: AWS CLI

```bash
aws stepfunctions start-execution \
  --state-machine-arn <step_function_arn> \
  --name gppa-dev-run-001
```

Execution order:

1. Bronze ingestion Glue job
2. Silver transform Glue job
3. Gold build Glue job

Success criteria:

- State machine ends with Succeeded
- All three Glue jobs complete successfully

---

## Step 8: Validate cloud outputs and quality

Why: verify data integrity and operational reliability after execution.

Check S3 outputs:

- bronze/
- silver/
- gold/
- quarantine/
- audit/

Key audit files:

- audit/bronze_run_report.csv
- audit/silver_quality_report.csv
- audit/metrics.csv
- audit/checkpoints.json

Check monitoring:

- CloudWatch alarm for dq_failure_count
- CloudWatch alarm for freshness_lag_hours

Success criteria:

- Curated datasets exist in Silver and Gold
- Quality report has expected structure and values
- No active critical alarms unless intended for testing

---

## Step 9: Query analytics layer and connect BI

Why: expose business-ready insights for analysts and stakeholders.

Run analytical SQL views:

- analytics/sql/gold_views/power_generation_dashboard.sql
- analytics/sql/gold_views/plant_operations_dashboard.sql
- analytics/sql/monitoring/data_quality_monitoring.sql

Use these contracts for dashboard setup:

- dashboards/quicksight/kpi_mapping.md
- dashboards/superset/dataset_contract.md

Success criteria:

- Views execute successfully
- KPI-level numbers match Gold outputs

---

## Step 10: Enable CI/CD execution path

Why: make deployments and validations repeatable and auditable.

Workflows:

- .github/workflows/ci.yml
- .github/workflows/dbt-ci.yml
- .github/workflows/deploy-dev.yml

What each does:

- ci.yml: pipeline tests + Terraform validation
- dbt-ci.yml: local simulation + dbt run/test contracts
- deploy-dev.yml: Terraform apply + Glue code upload

Success criteria:

- PR checks pass
- Manual dispatch deploy-dev works with configured secrets

---

## Step 11: Promote to QA and PROD

Why: standardize environment promotion with the same validated pattern.

Repeat for qa/prod:

1. Fill tfvars
2. terraform init/plan/apply
3. upload glue code
4. execute Step Functions
5. validate outputs/alarms

Recommendation:

- Promote only after dev validation artifacts are reviewed
- Keep parameter and schedule differences explicit by environment

---

## 6. Explainability notes (for interviews and stakeholder walkthroughs)

## 6.1 Why medallion?

- Bronze preserves raw fidelity and replayability
- Silver enforces data quality and semantic consistency
- Gold optimizes analyst usability and BI performance

## 6.2 Why Step Functions + Glue?

- Step Functions gives explicit orchestration and retries
- Glue provides managed ETL jobs with scalable workers
- Together they provide clear operational lineage

## 6.3 Why Terraform?

- Environment parity (dev/qa/prod)
- Repeatable, reviewable infrastructure changes
- Easy rollback via version control and plans

## 6.4 Why dbt in this stack?

- Contract-based analytics model checks
- Faster confidence for downstream reporting quality
- CI-friendly model and test execution

## 6.5 How idempotency is handled

- Checkpoint state + file hashes in audit/checkpoints.json
- Re-ingesting same source does not duplicate Bronze records in logic path
- Silver dedupe retains latest record per plant_id

---

## 7. Cost-aware implementation guidance

- Keep Glue worker count low in dev
- Run schedules less frequently in dev
- Use Athena for ad-hoc analytics before enabling heavier warehouses
- Apply lifecycle policies to optimize long-term S3 costs

---

## 8. Common failure scenarios and fixes

1. Glue job fails with script not found
- Cause: code not uploaded to expected S3 path
- Fix: run scripts/upload_glue_code.sh again

2. Step Functions fails at first task
- Cause: IAM permissions or missing Glue job name
- Fix: re-check Terraform outputs and IAM role attachments

3. Empty Gold tables
- Cause: Silver malformed ratio too high or no valid input
- Fix: inspect quarantine and quality report

4. dbt test failures
- Cause: source mappings/schema drift
- Fix: verify analytics/dbt/models/sources.yml and fixture prep script

---

## 9. Final go-live checklist

- Local tests and dbt checks pass
- Terraform validate passes for all environments
- DEV end-to-end execution succeeds
- S3 outputs and quality reports verified
- CloudWatch alarms configured and tested
- CI workflows passing
- QA and PROD parameter files prepared

---

## 10. Reference files

- docs/architecture.md
- docs/diagrams/architecture.mmd
- docs/runbooks/operations.md
- orchestration/step_functions/power_pipeline.asl.json
- scripts/upload_glue_code.sh
- scripts/local_simulate_incremental.py
- scripts/dbt_prepare_duckdb.py
- .github/workflows/ci.yml
- .github/workflows/dbt-ci.yml
- .github/workflows/deploy-dev.yml
