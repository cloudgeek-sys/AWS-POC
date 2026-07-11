# Operations Runbook

## Pipeline operations

1. Trigger orchestration state machine with parameters:
- run_mode: scheduled | replay
- replay_start_date / replay_end_date for bounded replay

2. Verify job status:
- Step Functions execution graph
- CloudWatch log groups per Glue job

3. Validate outputs:
- Bronze ingest partitions created
- Silver row counts and quarantine thresholds
- Gold fact and dimension tables refreshed

## Failure recovery

- Ingestion failure:
  - inspect source connectivity/file schema
  - rerun ingestion with same window (idempotent)
- Silver failure:
  - inspect quarantine samples and DQ metrics
  - fix mapping/schema and replay affected window
- Gold failure:
  - verify dependent Silver partitions exist
  - rerun Gold build for impacted years only

## Data quality SLOs (initial)

- Duplicate plant_id in Silver: 0
- Mandatory null rate (plant_name,country,primary_fuel,capacity_mw): < 0.5%
- Freshness lag for scheduled run: < 24h
- Quarantine ratio: < 2%

## Security controls

- IAM separation:
  - Data Engineer role: read/write bronze/silver/gold + orchestration
  - Analyst role: read silver/gold only
  - Dashboard role: read gold and Athena/QuickSight datasets

- Mask owner/operator metadata in Gold by default

## Change management

- All schema changes via pull request
- Update schema registry in pipelines/schemas
- Add migration note in docs/adrs for breaking changes
