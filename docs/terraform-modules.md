# Terraform Module Graph

Generated from `terraform/main.tf`.

```mermaid
graph TD
    storage["storage\n./modules/storage"]
    ingestion["ingestion\n./modules/ingestion"]
    search["search\n./modules/search"]
    frontend["frontend\n./modules/frontend"]
    storage -->|s3_bucket_arn| ingestion
    storage -->|s3_bucket_name| ingestion
    storage -->|dynamodb_table_name| ingestion
    storage -->|dynamodb_table_arn| ingestion
    ingestion -->|opensearch_endpoint| search
    ingestion -->|opensearch_collection_arn| search
    storage -->|s3_bucket_name| frontend
    storage -->|s3_bucket_arn| frontend
    search -->|api_url| frontend
```

## Module Wiring

| Module | Source | Inputs |
|---|---|---|
| `storage` | `./modules/storage` | `bucket_name` = `local.bucket_name`<br>`table_name` = `var.table_name` |
| `ingestion` | `./modules/ingestion` | `s3_bucket_arn` = `module.storage.s3_bucket_arn`<br>`s3_bucket_name` = `module.storage.s3_bucket_name`<br>`table_name` = `module.storage.dynamodb_table_name`<br>`table_arn` = `module.storage.dynamodb_table_arn`<br>`collection_name` = `var.collection_name`<br>`aws_region` = `var.aws_region` |
| `search` | `./modules/search` | `opensearch_endpoint` = `module.ingestion.opensearch_endpoint`<br>`collection_arn` = `module.ingestion.opensearch_collection_arn`<br>`collection_name` = `var.collection_name`<br>`aws_region` = `var.aws_region` |
| `frontend` | `./modules/frontend` | `aws_region` = `var.aws_region`<br>`collection_name` = `var.collection_name`<br>`s3_bucket_name` = `module.storage.s3_bucket_name`<br>`s3_bucket_arn` = `module.storage.s3_bucket_arn`<br>`search_api_url` = `module.search.api_url` |
