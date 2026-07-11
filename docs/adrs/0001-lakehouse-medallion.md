# ADR-0001: Medallion Lakehouse with Kimball Gold Layer

## Status
Accepted

## Context
The platform must support large-scale batch + incremental data engineering for global power plant analytics, with strong reproducibility and governance while remaining cost-effective on AWS personal credits.

## Decision
Adopt a medallion architecture on S3:
- Bronze for immutable raw ingestion
- Silver for conformed, validated datasets
- Gold for dimensional analytics models

Use Kimball-style dimensions and fact tables in Gold to support BI-friendly access patterns and governance.

## Consequences
Pros:
- Clear separation of concerns and data quality boundaries
- Strong replayability and lineage
- Flexible query engines (Athena now, Redshift later)
- Supports future scale and multi-domain expansion

Cons:
- More pipeline stages and metadata management overhead
- Requires strict naming conventions and schema discipline

## Alternatives considered
- Single-layer raw-to-reporting: rejected (poor governance, brittle analytics)
- Data vault everywhere: rejected for initial phase due to complexity and slower BI adoption

## Trade-offs
- Keep Bronze/Silver/Gold strict, while using lightweight quality framework first
- Add Iceberg ACID tables once incremental upsert volume grows

## Implementation updates 

- BI scope standardized to AWS QuickSight only; Superset is out of active delivery scope.
- Terraform state source of truth is remote S3 backend; local terraform state and plan artifacts are treated as disposable workspace files.
- Post-deploy reliability gate is mandatory through smoke checks (Step Functions, S3 code presence, QuickSight assets, representative Athena view checks).
- Dashboard proof artifacts for delivery and sign-off are maintained as PDF evidence files under dashboards/.
