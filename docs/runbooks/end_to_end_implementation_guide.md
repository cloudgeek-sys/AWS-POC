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

## 2.1 Deployed resource baseline (current)

- AWS Account: `371170753734`
- AWS Region: `us-east-1`
- Step Functions state machine ARN: `arn:aws:states:us-east-1:371170753734:stateMachine:gppa-main-power-pipeline`
- Data lake bucket: `gppa-main-lake-platform-20260710212811`
- Athena workgroup: `gppa-main-wg`
- Glue jobs:
  - `gppa-main-bronze-ingest-power-plants`
  - `gppa-main-silver-transform-power-plants`
  - `gppa-main-gold-build-power-analytics`
  - `gppa-main-visualizations-build`
- Glue crawlers:
  - `gppa-main-bronze-crawler`
  - `gppa-main-silver-crawler`
  - `gppa-main-gold-crawler`
- QuickSight Athena data source ARN: `arn:aws:quicksight:us-east-1:371170753734:datasource/gppa_main_athena`

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

- infra/terraform: IaC modules and a single environment stack (main)
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
cd /home/sagp/GPP_POC
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

## Step 4: Configure Terraform variables for the deployment environment

Why: establish deployment parameters and globally unique bucket names.

Files to prepare:

- infra/terraform/environments/main/terraform.tfvars

Start from examples:

- infra/terraform/environments/main/terraform.tfvars.example

Minimum values to set:

- aws_region
- project_name
- environment
- data_lake_bucket_suffix (must be globally unique)
- glue_job_worker_count
- schedule_expression

Explanation tip:

Use low Glue worker count in main to control cost, then tune as workloads grow.

---

## Step 5: Deploy MAIN infrastructure with Terraform

Why: provision all AWS runtime components for the pipeline.

Commands:

```bash
cd infra/terraform/environments/main
terraform init
terraform plan
terraform apply
cd ../../../..
```

What gets provisioned:

- S3 lake bucket and lifecycle policy
- IAM roles/policies for Glue and Step Functions
- Glue catalog databases, crawlers, and four Glue jobs (Bronze/Silver/Gold/Visualization)
- Athena workgroup
- Step Functions state machine
- CloudWatch alarms and log groups
- QuickSight Athena data source and datasets

Success criteria:

- Terraform apply completes with no errors
- Outputs include data_lake_bucket and step_function_arn

---

## Step 6: Upload Glue code to S3

Why: Glue jobs reference script locations in S3, so local code must be synced.

Command (recommended):

```bash
scripts/upload_glue_code.sh --env-dir infra/terraform/environments/main
```

Alternative command:

```bash
scripts/upload_glue_code.sh --bucket gppa-main-lake-platform-20260710212811
```

What this does:

- Syncs pipelines/ to s3://gppa-main-lake-platform-20260710212811/code/pipelines
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
  --state-machine-arn arn:aws:states:us-east-1:371170753734:stateMachine:gppa-main-power-pipeline \
  --name gppa-main-run-$(date +%s)
```

Execution order:

1. Bronze ingestion Glue job
2. Silver transform Glue job
3. Gold build Glue job
4. Visualization build Glue job

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
- visualizations/

Key audit files:

- audit/bronze_run_report.csv
- audit/silver_quality_report.csv
- audit/metrics.csv
- audit/checkpoints.json

Key visualization files:

- visualizations/capacity_by_country.png
- visualizations/fuel_mix_capacity.png
- visualizations/manifest.json

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

Success criteria:

- Views execute successfully
- KPI-level numbers match Gold outputs

---

## Step 10: Enable CI/CD execution path

Why: make deployments and validations repeatable and auditable.

Workflows:

- .github/workflows/ci.yml
- .github/workflows/dbt-ci.yml
- .github/workflows/deploy-main.yml

What each does:

- ci.yml: pipeline tests + Terraform validation
- dbt-ci.yml: local simulation + dbt run/test contracts
- deploy-main.yml: Terraform apply + Glue code upload + QuickSight dataset refresh + smoke checks

Post-deploy validation commands (local fallback):

1. Refresh QuickSight datasets:

  scripts/refresh_quicksight_datasets.sh gppa-main

1. Run smoke checks:

  scripts/post_deploy_smoke_check.sh gppa-main

Expected success output snippets:

- `Post-deploy smoke checks passed.`
- `OK: required datasets present`
- `OK: dashboard coverage present (power generation, plant operations, sustainability, monitoring)`
- `OK: Power Generation view -> <row_count>`

Success criteria:

- PR checks pass
- Manual dispatch deploy-main works with configured secrets

---

## Step 11: Operate and scale the single deployment environment

Why: keep one stable environment and run repeatable release cycles.

Repeat for each release:

1. Update tfvars if needed
2. terraform plan/apply in main
3. upload glue code
4. refresh QuickSight datasets
5. run post-deploy smoke checks
6. execute Step Functions
7. validate outputs/alarms

Recommendation:

- Apply changes only after main validation artifacts are reviewed
- Keep parameter and schedule changes explicit in version control

### Alerting operations (email)

- CloudWatch alarms publish to SNS topic: `gppa-main-alarm-notifications`
- Email endpoint configured: `sagarbabupullagura34@gmail.com`

Important:

1. Email delivery starts only after SNS subscription confirmation.
1. Confirm by opening the SNS email and selecting `Confirm subscription`.

### Concurrency operations (Step Functions -> Glue)

The deployment includes these protections against Glue concurrency contention:

- Glue job execution property `max_concurrent_runs = 2`
- Step Functions retry on `Glue.ConcurrentRunsExceededException` (60s interval, 10 attempts, 1.5x backoff)

If `ConcurrentRunsExceededException` still appears:

1. Check whether another pipeline execution is already in progress.
1. Wait for current Glue job completion and rerun Step Functions.
1. Increase `max_concurrent_job_runs` in `infra/terraform/environments/main/terraform.tfvars` only if cost/quota allows.

---

## Step 12: Clean bootstrap plus live Kaggle run (copy and execute)

Why: run the full platform from scratch in one sequence with the latest Kaggle dataset.

Pre-setup:

1. Configure Kaggle credentials in shell or ~/.kaggle/kaggle.json
2. Ensure Kaggle source is enabled in pipelines/configs/sources.yaml

Bootstrap and deploy:

1. python3 -m venv .venv
2. source .venv/bin/activate
3. pip install -r pipelines/requirements.txt
4. terraform -chdir=infra/terraform/environments/main init
5. terraform -chdir=infra/terraform/environments/main plan
6. terraform -chdir=infra/terraform/environments/main apply
7. scripts/upload_glue_code.sh --env-dir infra/terraform/environments/main

Optional local Kaggle verification:

1. .venv/bin/python -m pipelines.bronze.ingest_power_plants --config pipelines/configs/sources.yaml --data-root artifacts/local_kaggle_test --source-base . --force-replay
2. Verify bronze file exists under artifacts/local_kaggle_test/bronze for kaggle_global_power_plants.parquet

Cloud execution and verification:

1. Start orchestration:

  aws stepfunctions start-execution --state-machine-arn "$(terraform -chdir=infra/terraform/environments/main output -raw step_function_arn)" --name "gppa-main-run-$(date +%s)"

1. Check status:

  aws stepfunctions list-executions --state-machine-arn "$(terraform -chdir=infra/terraform/environments/main output -raw step_function_arn)" --max-results 5 --query "executions[].{name:name,status:status,start:startDate}" --output table

1. Check latest Glue job states:

  aws glue get-job-runs --job-name gppa-main-bronze-ingest-power-plants --max-results 1 --query "JobRuns[0].{State:JobRunState,Started:StartedOn,Completed:CompletedOn,Error:ErrorMessage}" --output table
  aws glue get-job-runs --job-name gppa-main-silver-transform-power-plants --max-results 1 --query "JobRuns[0].{State:JobRunState,Started:StartedOn,Completed:CompletedOn,Error:ErrorMessage}" --output table
  aws glue get-job-runs --job-name gppa-main-gold-build-power-analytics --max-results 1 --query "JobRuns[0].{State:JobRunState,Started:StartedOn,Completed:CompletedOn,Error:ErrorMessage}" --output table

1. Validate data artifacts:

  BUCKET="$(terraform -chdir=infra/terraform/environments/main output -raw data_lake_bucket)"
  aws s3 ls "s3://$BUCKET/bronze/" --recursive | head
  aws s3 ls "s3://$BUCKET/silver/" --recursive | head
  aws s3 ls "s3://$BUCKET/gold/" --recursive | head
  aws s3 ls "s3://$BUCKET/audit/" --recursive | head

Success criteria:

- Step Functions status is SUCCEEDED
- All three Glue jobs are SUCCEEDED
- Bronze includes kaggle_global_power_plants.parquet
- Silver, Gold, and Audit artifacts exist in S3
- Visualization artifacts exist in `visualizations/`

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

- Repeatable infrastructure behavior across releases
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

- Keep Glue worker count low in main
- Run schedules less frequently in main
- Use Athena for ad-hoc analytics before enabling heavier warehouses
- Apply lifecycle policies to optimize long-term S3 costs

---

## 8. Common failure scenarios and fixes

1. Glue job fails with script not found

- Cause: code not uploaded to expected S3 path
- Fix: run scripts/upload_glue_code.sh again

1. Step Functions fails at first task

- Cause: IAM permissions or missing Glue job name
- Fix: re-check Terraform outputs and IAM role attachments

1. Empty Gold tables

- Cause: Silver malformed ratio too high or no valid input
- Fix: inspect quarantine and quality report

1. dbt test failures

- Cause: source mappings/schema drift
- Fix: verify analytics/dbt/models/sources.yml and fixture prep script

---

## 9. Final go-live checklist

- Local tests and dbt checks pass
- Terraform validate passes for the deployment environment
- MAIN end-to-end execution succeeds
- S3 outputs and quality reports verified
- CloudWatch alarms configured and tested
- CI workflows passing
- Deployment environment parameter file prepared

---

## 10. Reference files

- docs/diagrams/architecture.md
- docs/diagrams/architecture.mmd
- orchestration/step_functions/power_pipeline.asl.json
- scripts/upload_glue_code.sh
- scripts/local_simulate_incremental.py
- scripts/dbt_prepare_duckdb.py
- .github/workflows/ci.yml
- .github/workflows/dbt-ci.yml
- .github/workflows/deploy-main.yml

---

## 11. Operations and incident handling

### 11.1 Standard pipeline operations

1. Trigger orchestration run.
2. Verify Step Functions and Glue job states.
3. Validate Bronze/Silver/Gold/Audit outputs.
4. Run post-deploy smoke check and archive evidence.

Core command:

```bash
scripts/post_deploy_smoke_check.sh gppa-main --report-file artifacts/local/audit/smoke-check-main.json
```

### 11.2 Failure recovery playbook

- Ingestion failure: inspect source connectivity/schema and rerun ingest.
- Silver failure: inspect quarantine + quality report, fix schema/mapping, replay window.
- Gold failure: verify Silver availability, rerun Gold build for impacted scope.
- Dashboard data issues: rerun Athena view deployment and refresh QuickSight datasets.

Recovery helpers:

```bash
eval "$(scripts/assume_persona_role.sh data-engineer)"
./scripts/run_athena_dashboard_views.sh
scripts/refresh_quicksight_datasets.sh gppa-main
```

### 11.3 Data quality SLOs

- Duplicate plant_id in Silver: 0
- Mandatory null rate (plant_name,country,primary_fuel,capacity_mw): < 0.5%
- Freshness lag for scheduled run: < 24h
- Quarantine ratio: < 2%

### 11.4 Monitoring and alerts verification

```bash
aws cloudwatch list-metrics --namespace GPPA/Pipeline --region us-east-1 --query 'Metrics[].MetricName' --output text
aws cloudwatch describe-alarms --alarm-name-prefix gppa-main- --region us-east-1 --query 'MetricAlarms[].AlarmName' --output table
aws logs describe-log-groups --log-group-name-prefix /aws-glue/jobs/gppa-main --region us-east-1 --output table
aws logs describe-log-groups --log-group-name-prefix /aws/vendedlogs/states/gppa-main-power-pipeline --region us-east-1 --output table
```

---

## 12. Sign-off and release gate

### 12.1 Required sign-off checks

- Latest Step Functions execution status is SUCCEEDED.
- Glue Bronze/Silver/Gold/Visualization latest runs are SUCCEEDED.
- S3 layer outputs exist for bronze, silver, gold, quarantine, audit.
- Smoke-check report status is passed.
- Athena sanity queries return expected records.
- CI workflows are green.

### 12.2 Evidence artifacts to retain

- `artifacts/local/audit/smoke-check-main.json`
- `artifacts/local/audit/bronze_run_report.csv`
- `artifacts/local/audit/silver_quality_report.csv`
- `artifacts/local/audit/checkpoints.json`
- Dashboard evidence PDFs under `dashboards/`

---

## 13. Requirement coverage summary

| Requirement area | Coverage |
| --- | --- |
| End-to-end orchestration | Step Functions + Glue Bronze/Silver/Gold/Visualization |
| Incremental + replay | Hash/checkpoint ingestion and replay controls |
| Medallion architecture | S3 Bronze/Silver/Gold + quarantine + audit |
| Data quality and reliability | Schema/null/range/duplicate checks + quarantine + metrics |
| Analytics readiness | Gold facts/dimensions + Athena views + QuickSight mapping |
| Monitoring and alerts | CloudWatch metrics/logs/alarms + smoke-check automation |
| IaC and CI/CD | Terraform modules + GitHub workflows |
