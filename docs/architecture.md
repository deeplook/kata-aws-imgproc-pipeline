# Solution Architecture

This page describes the completed `solution` branch.

## Runtime Flow

```mermaid
flowchart LR
    User[User Browser]
    App[App Runner Gallery]
    S3[S3 Bucket]
    Ingest[Ingest Lambda]
    Rekognition[Amazon Rekognition]
    Bedrock[Amazon Bedrock Titan Embed]
    DynamoDB[DynamoDB Metadata]
    AOSS[OpenSearch Serverless]
    APIGW[API Gateway]
    Search[Search Lambda]

    User --> App
    App -->|upload image| S3
    S3 --> Ingest
    Ingest --> Rekognition
    Ingest --> Bedrock
    Ingest --> DynamoDB
    Ingest --> AOSS
    App -->|search / search-by-image| APIGW
    APIGW --> Search
    Search --> Bedrock
    Search --> AOSS
    Search --> APIGW
    APIGW --> App
```

## Terraform Structure

The solution is split into four Terraform modules:

- `storage`: S3 bucket and DynamoDB table
- `ingestion`: ingest Lambda, IAM, and OpenSearch collection setup
- `search`: search Lambda and API Gateway
- `frontend`: ECR image build/push and App Runner service

For a generated view of how those modules are wired together, see [terraform-modules.md](terraform-modules.md).
