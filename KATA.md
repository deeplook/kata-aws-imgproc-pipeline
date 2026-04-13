# Coding Kata: Intelligent Semantic Photo Gallery on AWS

Build a fully serverless, AI-powered image processing pipeline — stage by stage, from a bare Lambda skeleton to a production-ready semantic search system.

---

## What You Are Building

An event-driven pipeline with semantic search:

1. A user uploads a photo to **S3**
2. S3 emits an `ObjectCreated` event that **triggers the ingest Lambda**
3. Lambda calls **Amazon Rekognition** to extract visual labels
4. Lambda calls **Amazon Bedrock** (Titan Embed Image) to generate a 1024-dimensional semantic embedding
5. Lambda writes structured metadata to **DynamoDB**
6. Lambda indexes the embedding in **OpenSearch Serverless**
7. A **search Lambda** exposed via **API Gateway** accepts natural-language queries and returns semantically ranked results

The finished system is ~200 lines of Python, a Terraform module structure, and a Makefile that orchestrates the entire lifecycle.

---

## Learning Objectives

By completing this kata you will be able to:

1. Build a multi-stage event-driven pipeline with S3 → Lambda
2. Integrate Amazon Rekognition for automatic image labeling via `detect_labels`
3. Write metadata to DynamoDB using `put_item` and `update_item`
4. Generate semantic embeddings with Amazon Bedrock Titan Embed Image via `invoke_model`
5. Index and query vector embeddings in OpenSearch Serverless using `opensearch-py` with SigV4 auth
6. Expose a Lambda as a REST endpoint using API Gateway HTTP API
7. Package Lambda functions with third-party dependencies (opensearch-py, requests-aws4auth)
8. Model least-privilege IAM in Terraform, growing permissions one stage at a time
9. Automate the full lifecycle with Make: `deploy → upload → smoke → destroy`

---

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | ≥ 1.3 | Infrastructure provisioning |
| Python | 3.12 | Lambda runtime and local tooling |
| [uv](https://github.com/astral-sh/uv) | latest | Python dependency management |
| AWS CLI | v2 | Credentials, log tailing |

AWS credentials must be configured (`aws configure` or environment variables) with permissions for Lambda, S3, IAM, Rekognition, Bedrock, DynamoDB, OpenSearch Serverless, and API Gateway.

---

## Repository Layout (completed state)

```
kata-aws-imgproc-pipeline/
├── KATA.md                          # this file
├── README.md
├── Makefile                         # lifecycle automation
├── pyproject.toml                   # Python dependencies
├── .python-version                  # 3.12
├── lambdas/
│   ├── ingest/handler.py            # ingest Lambda (Stages 1–5)
│   └── search/handler.py            # search Lambda (Stage 6)
└── terraform/
    ├── main.tf                      # root module
    ├── variables.tf, outputs.tf, versions.tf
    └── modules/
        ├── storage/                 # S3 + DynamoDB
        ├── ingestion/               # ingest Lambda + Rekognition + OpenSearch
        └── search/                  # search Lambda + API Gateway
```

---

## How the Skeleton Works

The repository pre-provides the complete Terraform module structure (with `???` placeholders), all Makefile targets (stubbed where noted), and Python stubs for both Lambda handlers. Your job is to fill in the Python code and Terraform resources stage by stage.

| Stage | What you fill in |
|-------|-----------------|
| 1 | `lambdas/ingest/handler.py` — log event, return 200; Terraform S3 + Lambda |
| 2 | `lambdas/ingest/handler.py` — Rekognition `detect_labels` |
| 3 | `lambdas/ingest/handler.py` — DynamoDB `put_item`; Terraform DynamoDB table |
| 4 | `lambdas/ingest/handler.py` — Bedrock `invoke_model`, store embedding |
| 5 | `lambdas/ingest/handler.py` — OpenSearch index; Terraform collection + policies |
| 6 | `lambdas/search/handler.py` — embed query, k-NN search; Terraform search Lambda + API GW |
| 7 | Both handlers — error handling; Makefile smoke targets; `make e2e` |

---

## The Stages

### Stage 1 — S3 → Lambda Hello

**Goal:** Deploy an ingest Lambda triggered by S3 `ObjectCreated` events. Confirm it receives and logs the S3 event.

#### Instructions

1. **Bootstrap your workspace:**

```bash
make install
make setup
```

`install` runs `uv sync`; `setup` runs `terraform init`. You won't deploy yet — Terraform comes after writing the Python stub.

2. Open `lambdas/ingest/handler.py`. The stub defines `lambda_handler(event, context)`.
3. Inside the handler:
   - Print a startup message (e.g. `"Ingest Lambda invoked"`)
   - Print the full event as JSON
   - Extract `bucket_name` and `object_key` from `event["Records"][0]["s3"]`
   - URL-decode the object key using `urllib.parse.unquote_plus` — S3 encodes spaces as `+`
   - Return `{"statusCode": 200, "body": json.dumps({"key": object_key})}`
4. Open `terraform/modules/storage/main.tf` and fill in the S3 bucket resource (replace `"???"` with the correct values).
5. Open `terraform/modules/ingestion/main.tf` and fill in:
   - The IAM role's `assume_role_policy` (already done — review it)
   - The Lambda function's `role`, `handler`, `runtime`, `filename`, `source_code_hash`
   - The `aws_lambda_permission` `source_arn`
   - The `aws_s3_bucket_notification` `bucket` and `lambda_function_arn`
6. Deploy:

```bash
make deploy
make upload
make logs-ingest
```

#### Verification
- `make logs-ingest` shows a CloudWatch entry with the S3 object key
- The handler returns `{"statusCode": 200, "body": "{\"key\": \"test-image.jpg\"}"}`

<details>
<summary>Hints</summary>

- S3 event structure:
  ```python
  bucket_name = event["Records"][0]["s3"]["bucket"]["name"]
  raw_key = event["Records"][0]["s3"]["object"]["key"]
  object_key = urllib.parse.unquote_plus(raw_key, encoding="utf-8")
  ```
- `print()` in Lambda writes directly to CloudWatch — no logging setup needed
- S3 bucket names are globally unique across all AWS accounts — use a suffix (e.g. account ID) to avoid collisions. In `terraform/main.tf`:
  ```hcl
  data "aws_caller_identity" "current" {}
  locals {
    bucket_name = "${var.bucket_name}-${data.aws_caller_identity.current.account_id}"
  }
  ```
  Pass `local.bucket_name` to the storage module instead of `var.bucket_name`.
- If Rekognition returns `InvalidImageFormatException` in Stage 2, verify the test image is a real JPEG or PNG — `file test-image.jpg` will tell you.
- Lambda handler skeleton:
  ```python
  import json
  import urllib.parse

  def lambda_handler(event, context):
      print("Ingest Lambda invoked")
      print(json.dumps(event))
      bucket_name = event["Records"][0]["s3"]["bucket"]["name"]
      raw_key = event["Records"][0]["s3"]["object"]["key"]
      object_key = urllib.parse.unquote_plus(raw_key, encoding="utf-8")
      print(f"Processing: s3://{bucket_name}/{object_key}")
      return {"statusCode": 200, "body": json.dumps({"key": object_key})}
  ```
- Terraform Lambda function (fill in the `???` fields):
  ```hcl
  resource "aws_lambda_function" "ingest" {
    function_name    = "ingest-lambda"
    role             = aws_iam_role.ingest_exec.arn
    handler          = "handler.lambda_handler"
    runtime          = "python3.12"
    filename         = data.archive_file.ingest_zip.output_path
    source_code_hash = data.archive_file.ingest_zip.output_base64sha256
    timeout          = 60
    ...
  }
  ```
- The `archive_file` data source already points to `lambdas/ingest/handler.py` — Terraform will zip it during `plan`
- The `depends_on = [aws_lambda_permission.allow_s3]` on the S3 notification is critical — S3 needs the permission to exist before it can save the notification config
</details>

**Key Concepts**
> - Lambda handler signature: `def lambda_handler(event, context)` — always present
> - S3 URL-encodes object keys in event notifications — always decode with `unquote_plus` before using
> - `aws_lambda_permission` gives S3 service-level permission to invoke; IAM role policy grants the function's own outbound permissions — both are required
> - `depends_on` enforces creation order when Terraform can't infer it from resource references

---

### Stage 2 — Rekognition Labels

**Goal:** Call Amazon Rekognition to detect visual labels in the uploaded image and log them.

#### Instructions

1. Import `boto3` and create a Rekognition client inside `lambda_handler` (you'll move it to module scope in Stage 4).
2. After parsing the S3 key, call `detect_labels` passing an `S3Object` reference:
   - `MaxLabels=10`, `MinConfidence=75`
   - Do not download the image into Lambda — pass the S3 reference and let Rekognition fetch it
3. Extract labels from the response. Each label has `Name` and `Confidence`.
4. Log each label: `  - Dog: 98.45%`
5. Return the list of label names in the response body.
6. In `terraform/modules/ingestion/main.tf`, fill in the `rekognition:DetectLabels` IAM statement (replace `"???"`), then redeploy:

```bash
make deploy
make upload IMAGE=my-photo.jpg
make logs-ingest
```

#### Verification
- CloudWatch log entry contains lines like `  - Beach: 99.21%`
- The response body includes `"labels": ["Beach", "Ocean", ...]`

<details>
<summary>Hints</summary>

- `S3Object` means Rekognition fetches the image server-side — no Lambda bandwidth used:
  ```python
  import boto3

  rekognition = boto3.client("rekognition")
  response = rekognition.detect_labels(
      Image={"S3Object": {"Bucket": bucket_name, "Name": object_key}},
      MaxLabels=10,
      MinConfidence=75,
  )
  labels = response["Labels"]
  for label in labels:
      print(f"  - {label['Name']}: {label['Confidence']:.2f}%")
  ```
- `MinConfidence=75` filters low-confidence results — lower it to see more labels
- Rekognition must be in the same AWS region as the Lambda function to use S3Object references
- IAM statement to add:
  ```hcl
  {
    Action   = "rekognition:DetectLabels"
    Effect   = "Allow"
    Resource = "*"   # Rekognition does not support resource-level restrictions
  }
  ```
</details>

**Key Concepts**
> - `S3Object` vs inline bytes: passing `{"S3Object": {...}}` lets Rekognition fetch the image server-side — no data through Lambda
> - `MaxLabels` and `MinConfidence` are your primary knobs for result quality vs. quantity
> - `AccessDeniedException` means the IAM policy is missing `rekognition:DetectLabels` — check and redeploy
> - Lambda retries failed async invocations up to 2 times — you may see old events replayed after a fix is deployed; this is expected behaviour, not a bug

---

### Stage 3 — DynamoDB Metadata

**Goal:** Write image metadata — key, labels, upload timestamp — to DynamoDB after each upload.

#### Instructions

1. Import `boto3` and create a DynamoDB resource.
2. After the Rekognition call, write a record to the DynamoDB table:
   - `image_key`: the S3 object key (partition key)
   - `labels`: a list of label names
   - `upload_timestamp`: current UTC time as ISO 8601 string
3. Log `"DynamoDB: record written"` on success.
4. Open `terraform/modules/storage/main.tf`. Fill in the DynamoDB table resource:
   - `name`, `billing_mode`, `hash_key`, and the `attribute` block
5. In `terraform/modules/ingestion/main.tf`, fill in the DynamoDB IAM statement. Redeploy:

```bash
make deploy
make upload
aws dynamodb scan --table-name photo-metadata
```

#### Verification
- `aws dynamodb scan --table-name photo-metadata` returns at least one item
- The item contains `image_key`, `labels`, and `upload_timestamp` attributes

<details>
<summary>Hints</summary>

- DynamoDB resource and `put_item`:
  ```python
  import boto3
  import os
  from datetime import datetime, timezone

  dynamodb = boto3.resource("dynamodb")
  table = dynamodb.Table(os.environ["TABLE_NAME"])

  label_names = [label["Name"] for label in labels]
  table.put_item(Item={
      "image_key": object_key,
      "labels": label_names,
      "upload_timestamp": datetime.now(timezone.utc).isoformat(),
  })
  print("DynamoDB: record written")
  ```
- The `TABLE_NAME` environment variable is set by Terraform (already in the Lambda `environment` block — fill in the `???`)
- DynamoDB Terraform resource:
  ```hcl
  resource "aws_dynamodb_table" "metadata" {
    name         = var.table_name
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "image_key"

    attribute {
      name = "image_key"
      type = "S"
    }
  }
  ```
- IAM statement to add:
  ```hcl
  {
    Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
    Effect   = "Allow"
    Resource = var.table_arn
  }
  ```
- `PAY_PER_REQUEST` billing means no capacity planning — suitable for kata usage and burst-y workloads
</details>

**Key Concepts**
> - DynamoDB's `hash_key` is the partition key — `image_key` (the S3 object key) is a natural unique identifier
> - `PAY_PER_REQUEST` vs. `PROVISIONED`: pay-per-request has no idle cost and scales automatically; provisioned requires capacity planning
> - Environment variables are the standard mechanism for passing Terraform outputs (table name, endpoint) to Lambda code
> - `put_item` is an upsert — re-uploading the same key overwrites the existing item

---

### Stage 4 — Bedrock Embeddings

**Goal:** Generate a 1024-dimensional semantic embedding from the Rekognition labels using Amazon Bedrock Titan Embed Image, and store it in DynamoDB.

#### Instructions

1. Import `boto3` and create a Bedrock Runtime client.
2. After the DynamoDB write, prepare the embedding input:
   - Join the label names into a comma-separated string: `"Dog, Animal, Pet, Canine"`
   - Call `bedrock_runtime.invoke_model` with model `amazon.titan-embed-image-v1`
   - Request body (JSON): `{"inputText": label_string}`
3. Parse the response: `json.loads(response["body"].read())["embedding"]`
4. Log `f"embedding: {len(embedding)} dimensions"` — you should see `1024`
5. Update the DynamoDB item with the embedding:
   ```python
   from decimal import Decimal
   embedding_decimal = [Decimal(str(v)) for v in embedding]
   table.update_item(
       Key={"image_key": object_key},
       UpdateExpression="SET embedding = :e",
       ExpressionAttributeValues={":e": embedding_decimal},
   )
   ```
6. In `terraform/modules/ingestion/main.tf`, fill in the `bedrock:InvokeModel` IAM statement. Redeploy.

#### Verification
- CloudWatch log contains `"embedding: 1024 dimensions"`
- `aws dynamodb get-item --table-name photo-metadata --key '{"image_key":{"S":"test-image.jpg"}}'` shows an `embedding` attribute with 1024 numbers

<details>
<summary>Hints</summary>

- Bedrock Titan Embed Image call:
  ```python
  import boto3
  import json

  bedrock = boto3.client("bedrock-runtime")
  label_string = ", ".join(label_names)
  response = bedrock.invoke_model(
      modelId="amazon.titan-embed-image-v1",
      body=json.dumps({"inputText": label_string}),
      contentType="application/json",
      accept="application/json",
  )
  embedding = json.loads(response["body"].read())["embedding"]
  print(f"embedding: {len(embedding)} dimensions")
  ```
- The Titan model supports both `inputText` and `inputImage` (base64). Using `inputText` in the core kata keeps the code simple — you can add `inputImage` as a stretch goal
- boto3's DynamoDB *resource* client (`boto3.resource('dynamodb')`) does not accept Python `float`. Convert with `Decimal(str(v))`. The *client* (`boto3.client('dynamodb')`) accepts raw numbers — but requires manual type annotations.
- IAM statement to add:
  ```hcl
  {
    Action   = "bedrock:InvokeModel"
    Effect   = "Allow"
    Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-image-v1"
  }
  ```
- Note: Bedrock foundation model ARNs use `::` (no account ID) — this is intentional for AWS-managed models
- Move the Bedrock client to module scope (singleton pattern):
  ```python
  _BEDROCK_CLIENT = None

  def _get_bedrock_client():
      global _BEDROCK_CLIENT
      if _BEDROCK_CLIENT is None:
          _BEDROCK_CLIENT = boto3.client("bedrock-runtime")
      return _BEDROCK_CLIENT
  ```
</details>

**Key Concepts**
> - **Cold start vs. warm start**: module-level client initialization runs once per container lifetime; move expensive clients (Bedrock, OpenSearch) to module scope
> - Bedrock `invoke_model` is synchronous — it blocks until the model responds; 1024-dimension embeddings take ~200ms
> - `inputText` modality: Titan Embed Image accepts text and generates the same 1024-dimension space as image embeddings — useful when actual images aren't available or when embedding label strings
> - boto3's DynamoDB resource client rejects Python `float` — wrap with `Decimal(str(v))` before calling `update_item`. DynamoDB returns numbers as `Decimal` on read; cast to `float` if needed downstream (e.g. before passing to Bedrock)

---

### Stage 5 — OpenSearch Indexing

**Goal:** Index each image's embedding and metadata in OpenSearch Serverless, enabling k-NN semantic search.

#### Instructions

This is the most complex stage. It introduces third-party library packaging and a new AWS service.

1. **Terraform first** — OpenSearch Serverless collections take 5–10 minutes to become `ACTIVE`. Provision the infrastructure before writing Python:
   - In `terraform/modules/ingestion/main.tf`, fill in:
     - `aws_opensearchserverless_collection.gallery`: `name` and `type`
   - The encryption, network, and data access policies are already stubbed — review them
   - In the `aws_iam_role_policy.ingest_policy`, fill in the `aoss:APIAccessAll` statement
   - Redeploy and wait: `make deploy && make wait-opensearch`

2. **Rebuild the Lambda zip with dependencies:**

```bash
make package
make deploy   # re-packages and redeploys
```

3. **Write the Python** — in `lambdas/ingest/handler.py`:
   - Import `opensearchpy` and `requests_aws4auth`
   - Create an OpenSearch client using SigV4 auth (`service="aoss"`)
   - Create the index if it doesn't exist (k-NN mapping: 1024 dims, cosine space, HNSW engine)
   - Index the document: `image_key`, `labels`, `embedding`
   - Log `"OpenSearch: indexed"`

4. After deploying, upload an image and verify:

```bash
make upload
make logs-ingest   # confirm "OpenSearch: indexed"
```

#### Verification
- CloudWatch log contains `"OpenSearch: indexed"`
- `make search` (implemented after Stage 6) returns results, OR query OpenSearch directly:
  ```bash
  curl -XGET "$OPENSEARCH_ENDPOINT/photos/_count" \
    --aws-sigv4 "aws:amz:eu-central-1:aoss" \
    --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY"
  ```

<details>
<summary>Hints</summary>

- OpenSearch client with SigV4:
  ```python
  import os
  import boto3
  from opensearchpy import OpenSearch, RequestsHttpConnection
  from requests_aws4auth import AWS4Auth

  def _get_opensearch_client():
      global _OS_CLIENT
      if _OS_CLIENT is None:
          region = os.environ["AWS_REGION_NAME"]
          credentials = boto3.Session().get_credentials()
          awsauth = AWS4Auth(
              credentials.access_key,
              credentials.secret_key,
              region,
              "aoss",
              session_token=credentials.token,
          )
          endpoint = os.environ["OPENSEARCH_ENDPOINT"].removeprefix("https://")
          _OS_CLIENT = OpenSearch(
              hosts=[{"host": endpoint, "port": 443}],
              http_auth=awsauth,
              use_ssl=True,
              verify_certs=True,
              connection_class=RequestsHttpConnection,
          )
      return _OS_CLIENT
  ```
- Index creation (run once, idempotent):
  ```python
  INDEX_NAME = "photos"

  def _ensure_index(client):
      if not client.indices.exists(index=INDEX_NAME):
          client.indices.create(index=INDEX_NAME, body={
              "settings": {"index": {"knn": True}},
              "mappings": {
                  "properties": {
                      "image_key": {"type": "keyword"},
                      "labels": {"type": "keyword"},
                      "embedding": {
                          "type": "knn_vector",
                          "dimension": 1024,
                          "method": {
                              "name": "hnsw",
                              "space_type": "cosinesimil",
                              "engine": "nmslib",
                          },
                      },
                  }
              },
          })
  ```
- Indexing the document:
  ```python
  client = _get_opensearch_client()
  _ensure_index(client)
  client.index(index=INDEX_NAME, body={
      "image_key": object_key,
      "labels": label_names,
      "embedding": embedding,
  })
  print("OpenSearch: indexed")
  ```
- Check `terraform output opensearch_endpoint` — if it starts with `https://https://`, remove the extra prefix from your HCL. The `collection_endpoint` attribute already includes `https://`; do not prepend another scheme.
- If you see `IndicesClient.exists() takes 1 positional argument but 2 were given` (or `create()`), you are on opensearch-py v3 — pass all parameters as keyword arguments: `client.indices.exists(index=INDEX_NAME)`, `client.indices.create(index=INDEX_NAME, body={...})`
- OpenSearch Serverless does not support explicit document IDs via the index API — omit `id=` and rely on auto-generated IDs. The `image_key` field in the document body still identifies the source image for search results.
- OpenSearch Serverless requires the collection to be `ACTIVE` before indexing — `make wait-opensearch` polls for this
- The `OPENSEARCH_ENDPOINT` environment variable is set by Terraform; fill in the `???` in the Lambda environment block
- `make package` builds the Lambda zip with `opensearch-py` and `requests-aws4auth` bundled
- IAM statement for AOSS:
  ```hcl
  {
    Action   = "aoss:APIAccessAll"
    Effect   = "Allow"
    Resource = aws_opensearchserverless_collection.gallery.arn
  }
  ```
- After Stage 5, switch `archive_file` from `source_file` (single .py) to `source_dir` pointing to the pre-built package directory to include dependencies
</details>

**Key Concepts**
> - **Lambda dependency packaging**: the Lambda zip must bundle all third-party libraries not provided by the runtime — `boto3` is pre-installed, but `opensearch-py` is not
> - OpenSearch Serverless requires **three policies** before a collection can be created: encryption, network, and data access — Terraform enforces this via `depends_on`
> - **SigV4 with service=`aoss`**: OpenSearch Serverless uses IAM authentication, not HTTP Basic — `requests-aws4auth` signs each request with temporary credentials
> - HNSW + cosine space: standard configuration for approximate nearest-neighbor search with semantic embeddings

---

### Stage 6 — Search Lambda + API Gateway

**Goal:** Expose a `GET /search?q=<query>` endpoint that embeds the query and returns k-NN results from OpenSearch.

#### Instructions

1. Open `lambdas/search/handler.py`. Fill in the handler:
   - Extract `q` from `event["queryStringParameters"]`
   - Return `{"statusCode": 400, ...}` if the query is missing or empty
   - Embed the query text using Bedrock Titan Embed Image (`inputText`)
   - Run a k-NN search against OpenSearch (`k=5`)
   - Format results as `[{"key": ..., "score": ..., "labels": [...]}]`
   - Return `{"statusCode": 200, "body": json.dumps({"results": results})}`

2. Open `terraform/modules/search/main.tf`. Fill in all `???` values:
   - Lambda `role`, `handler`, `runtime`, `filename`, `source_code_hash`
   - Lambda environment variables: `OPENSEARCH_ENDPOINT`, `COLLECTION_NAME`, `AWS_REGION_NAME`
   - `aws_lambda_permission` `source_arn`
   - `aws_apigatewayv2_integration` `integration_uri`
   - `aws_apigatewayv2_route` `route_key` and `target`
   - IAM statements for `bedrock:InvokeModel` and `aoss:APIAccessAll`

3. In `terraform/modules/ingestion/main.tf`, also add the search Lambda's role to the OpenSearch data access policy's `Principal` list (or create a separate access policy for the search role).

4. Package and deploy:

```bash
make package
make deploy
```

5. Implement the `search` Makefile target:
   - Source `.tf_outputs.env`
   - `curl "$$API_URL/search?q=$(QUERY)"`

#### Verification
- `make search QUERY=beach` returns a JSON array with at least one result
- `make logs-search` shows the embedding dimensions and number of hits

<details>
<summary>Hints</summary>

- Search handler:
  ```python
  import json
  import os
  import boto3
  from opensearchpy import OpenSearch, RequestsHttpConnection
  from requests_aws4auth import AWS4Auth

  _BEDROCK_CLIENT = None
  _OS_CLIENT = None
  INDEX_NAME = "photos"

  def _get_bedrock_client():
      global _BEDROCK_CLIENT
      if _BEDROCK_CLIENT is None:
          _BEDROCK_CLIENT = boto3.client("bedrock-runtime")
      return _BEDROCK_CLIENT

  def _get_opensearch_client():
      # same as ingest — SigV4 with service="aoss"
      ...

  def lambda_handler(event, context):
      params = event.get("queryStringParameters") or {}
      query = params.get("q", "").strip()
      if not query:
          return {"statusCode": 400, "body": json.dumps({"message": "missing query parameter 'q'"})}

      bedrock = _get_bedrock_client()
      response = bedrock.invoke_model(
          modelId="amazon.titan-embed-image-v1",
          body=json.dumps({"inputText": query}),
          contentType="application/json",
          accept="application/json",
      )
      query_embedding = json.loads(response["body"].read())["embedding"]
      print(f"query embedding: {len(query_embedding)} dimensions")

      client = _get_opensearch_client()
      search_response = client.search(index=INDEX_NAME, body={
          "size": 5,
          "query": {
              "knn": {
                  "embedding": {
                      "vector": query_embedding,
                      "k": 5,
                  }
              }
          }
      })

      results = [
          {
              "key": hit["_source"]["image_key"],
              "score": hit["_score"],
              "labels": hit["_source"].get("labels", []),
          }
          for hit in search_response["hits"]["hits"]
      ]
      print(f"search: {len(results)} results")
      return {"statusCode": 200, "body": json.dumps({"results": results})}
  ```
- API Gateway HTTP API (`payload_format_version = "2.0"`) passes query parameters in `event["queryStringParameters"]` — it may be `None` if no params are provided, so always use `.get()` with a fallback
- The search Lambda needs its own OpenSearch data access policy. Creating a separate policy in the search module (rather than adding the search role to the ingest module's policy) avoids a cross-module dependency:
  ```hcl
  resource "aws_opensearchserverless_access_policy" "search_access" {
    name = "${var.collection_name}-search-access"
    type = "data"
    policy = jsonencode([{
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${var.collection_name}"]
          Permission   = ["aoss:DescribeCollectionItems"]
        },
        {
          ResourceType = "index"
          Resource     = ["index/${var.collection_name}/*"]
          Permission   = ["aoss:ReadDocument", "aoss:DescribeIndex"]
        },
      ]
      Principal = [aws_iam_role.search_exec.arn]
    }])
  }
  ```
- If the search Lambda returns `Internal error` and CloudWatch shows `index_not_found_exception` (404), the index exists but AOSS is masking a permissions error — check that the data access policy includes both collection-level `aoss:DescribeCollectionItems` AND index-level `aoss:ReadDocument`
- `aws_apigatewayv2_stage` with `auto_deploy = true` automatically deploys any route changes — no manual stage deployment needed
- The invoke URL format: `https://<api-id>.execute-api.<region>.amazonaws.com/search?q=beach`
- `make search` target implementation:
  ```makefile
  search:
  	@. .tf_outputs.env && curl -s "$$API_URL/search?q=$(QUERY)" | python3 -m json.tool
  ```
</details>

**Key Concepts**
> - API Gateway HTTP API (v2) vs REST API (v1): HTTP API is simpler, cheaper, and sufficient for proxy integrations — use REST API only when you need request validation, usage plans, or API keys
> - `payload_format_version = "2.0"`: required for HTTP API Lambda proxy — `event` structure differs from REST API (no `event["body"]` wrapping for GET requests)
> - Both `aws_lambda_permission` (service-level) and IAM role (function-level) are required for API Gateway to invoke Lambda — missing either gives a 5xx or permission error
> - AOSS data access policies require permissions at **two levels**: collection-level `aoss:DescribeCollectionItems` to use the collection endpoint, plus index-level `aoss:ReadDocument` to search — a missing collection-level entry causes AOSS to return `404 index_not_found_exception` even when the index exists (it masks the 403 to avoid leaking resource information)
> - The OpenSearch data access policy is separate from IAM — the IAM role grants `aoss:APIAccessAll` (network-level), while the data access policy grants document/index operations (data-level); both are required

---

### Stage 7 — IaC Polish + End-to-End

**Goal:** Add error handling and structured logging to both handlers, implement the smoke test Makefile targets, and run the full pipeline with `make e2e`.

#### Instructions

**`lambdas/ingest/handler.py`:**

1. Validate the event: check that `Records` exists and is non-empty; return `400` if not.
2. Wrap the entire pipeline in a `try/except` block. Catch `ClientError` from `botocore.exceptions` and log the AWS error code before returning `500`.
3. Log a structured summary at the end: `json.dumps({"key": object_key, "labels": label_names, "dimensions": len(embedding), "indexed": True})`

**`lambdas/search/handler.py`:**

1. Wrap the Bedrock call and OpenSearch query in `try/except`. Return `503` on connection errors, `500` on other errors.
2. Log a structured result: `json.dumps({"query": query, "results": len(results)})`

**`Makefile`:**

3. Implement `smoke-ingest`:
   - Source `.tf_outputs.env`
   - Poll the most recent CloudWatch log stream for `INGEST_LAMBDA`
   - Retry up to 20 times with 10-second intervals
   - Exit 0 when `"OpenSearch: indexed"` appears; exit 1 after timeout

4. Implement `smoke-search`:
   - Source `.tf_outputs.env`
   - `curl "$$API_URL/search?q=$(QUERY)"` and parse with `jq`
   - Exit 0 if `results` array is non-empty; exit 1 otherwise

5. Verify the full pipeline:

```bash
make e2e
```

#### Verification
- `make e2e` runs: `deploy → upload → smoke-ingest → search → smoke-search → destroy` and exits 0
- Invoking ingest with an empty payload returns `{"statusCode": 400, ...}`
- A search with a nonsense query returns `{"results": []}` rather than an error

<details>
<summary>Hints</summary>

- Ingest event validation:
  ```python
  from botocore.exceptions import ClientError

  if not event.get("Records"):
      return {"statusCode": 400, "body": json.dumps({"message": "Invalid event: no Records"})}
  ```
- Ingest try/except:
  ```python
  try:
      # ... Rekognition, DynamoDB, Bedrock, OpenSearch ...
      print(json.dumps({"key": object_key, "labels": label_names, "dimensions": len(embedding), "indexed": True}))
      return {"statusCode": 200, "body": json.dumps({"key": object_key, "labels": label_names})}
  except ClientError as e:
      code = e.response["Error"]["Code"]
      print(f"AWS error [{code}]: {e}")
      return {"statusCode": 500, "body": json.dumps({"message": f"AWS error: {code}"})}
  except Exception as e:
      print(f"Unexpected error: {e}")
      return {"statusCode": 500, "body": json.dumps({"message": "Internal error"})}
  ```
- `smoke-ingest` shell skeleton:
  ```makefile
  smoke-ingest:
  	@. .tf_outputs.env && \
  	LOG_GROUP="/aws/lambda/$$INGEST_LAMBDA"; \
  	echo "Polling $$LOG_GROUP for 'OpenSearch: indexed'..."; \
  	for i in $$(seq 1 20); do \
  		STREAM=$$(aws logs describe-log-streams \
  			--log-group-name "$$LOG_GROUP" \
  			--order-by LastEventTime --descending --limit 1 \
  			--query "logStreams[0].logStreamName" --output text 2>/dev/null); \
  		if aws logs get-log-events \
  			--log-group-name "$$LOG_GROUP" \
  			--log-stream-name "$$STREAM" \
  			--query "events[*].message" --output text 2>/dev/null \
  			| grep -q "OpenSearch: indexed"; then \
  			echo "smoke-ingest: PASSED"; exit 0; \
  		fi; \
  		echo "  attempt $$i/20 — not found yet, retrying in 10s..."; \
  		sleep 10; \
  	done; \
  	echo "smoke-ingest: FAILED — 'OpenSearch: indexed' not found after 20 attempts"; exit 1
  ```
- `smoke-search` skeleton:
  ```makefile
  smoke-search:
  	@. .tf_outputs.env && \
  	RESULTS=$$(curl -s "$$API_URL/search?q=$(QUERY)" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('results', [])))"); \
  	if [ "$$RESULTS" -gt 0 ]; then \
  		echo "smoke-search: PASSED ($$RESULTS results)"; exit 0; \
  	else \
  		echo "smoke-search: FAILED (0 results)"; exit 1; \
  	fi
  ```
- `.tf_outputs.env` is a shell script written by `make deploy` — it exports all Terraform outputs as shell variables; source it with `. .tf_outputs.env`
</details>

**Key Concepts**
> - Structured logging (JSON) makes log entries machine-readable — CloudWatch Insights can query them with `fields @message | filter indexed = true`
> - `smoke-test` is integration testing against observable side effects — it tests the real system, not mocks
> - `e2e` targets should be idempotent: `deploy → test → destroy` leaves no lingering state and no manual cleanup
> - The `make deploy` pattern of writing `.tf_outputs.env` decouples infrastructure outputs from scripts, matching the 12-factor app principle of config in the environment

---

## Solutions

The complete working implementation lives on the `solution` branch:

```bash
git checkout solution
```

| File | What to Study |
|------|--------------|
| `lambdas/ingest/handler.py` | Full pipeline, singleton clients, structured error handling |
| `lambdas/search/handler.py` | k-NN search, query embedding, result formatting |
| `terraform/modules/storage/main.tf` | S3 + DynamoDB resource configuration |
| `terraform/modules/ingestion/main.tf` | OpenSearch policies ordering, IAM least-privilege |
| `terraform/modules/search/main.tf` | API Gateway HTTP API wiring |
| `Makefile` | CloudWatch polling pattern, smoke test logic |

Attempt each stage independently before checking the solution branch.

---

## Stretch Goals

After completing all 7 stages:

1. **Image embeddings** — In Stage 4, switch from `inputText` (label string) to `inputImage` (base64-encoded image bytes). Fetch the image from S3 in Lambda, encode it, and pass it to Titan Embed Image.

2. **AppRunner frontend** — The cherry on top. Turn your invisible API into a real web gallery: upload photos from a browser, type a natural-language query, and see semantically ranked thumbnails — all backed by the pipeline you built in Stages 1–7.

   **What to build:**
   - A Python [FastAPI](https://fastapi.tiangolo.com/) web app with five endpoints:
     - `GET /` — serves the gallery HTML (embedded in the app, no separate static files needed)
     - `POST /upload` — accepts **one or more** multipart images and writes each to S3 with `put_object`
     - `GET /search?q=<query>` — proxies to your API Gateway search endpoint and enriches each result with a **presigned S3 GET URL** (1-hour TTL) so the browser can render thumbnails directly
     - `POST /search-by-image` — accepts a query image, runs it through Rekognition to extract labels, joins them into a text string, then calls the existing search API — reverse image search with no new infrastructure
     - `GET /stats` — proxies to a new `GET /count` route on the search Lambda (AOSS `_count` query) and returns the number of indexed images
   - A minimal but functional gallery UI: drag-and-drop upload (multiple files at once), a combined search card with a text field and an image drop zone, a live image count badge in the header, and a responsive image grid showing thumbnail, relevance score, and Rekognition labels
   - A **Dockerfile** (Python 3.12-slim, uvicorn on port 8080, built with `--platform linux/amd64` for App Runner compatibility)
   - A `terraform/modules/frontend/` Terraform module containing:
     - `aws_ecr_repository` — private container registry (`force_delete = true` for clean teardown)
     - `null_resource` with a `local-exec` provisioner — builds and pushes the Docker image to ECR during `terraform apply`, re-triggering whenever `Dockerfile`, `main.py`, or `pyproject.toml` change
     - Two IAM roles: an **access role** (`build.apprunner.amazonaws.com`) with the managed `AWSAppRunnerServicePolicyForECRAccess` policy for ECR pulls; an **instance role** (`tasks.apprunner.amazonaws.com`) with `s3:PutObject` + `s3:GetObject` on the image bucket
     - `aws_apprunner_service` pointing at the ECR image (`cpu = "256"`, `memory = "512"` — the minimum tier)

   **Key concepts:**
   > - **Presigned URLs** let the browser load images from a private S3 bucket without exposing credentials — the backend signs a time-limited GET URL and returns it in the search response
   > - **`null_resource` + `local-exec`**: Terraform's escape hatch for imperative steps (Docker build/push) that have no native provider resource. `triggers` on file hashes make it re-run only when app code changes
   > - **Two IAM roles for App Runner**: the *access role* is assumed by the App Runner control plane to pull the image from ECR; the *instance role* is assumed by your running container to call AWS APIs — both are required and have different trust principals
   > - **`--platform linux/amd64`**: App Runner only runs x86_64 containers — always pass this flag when building on Apple Silicon to avoid a silent architecture mismatch
   > - App Runner provisions HTTPS automatically; no certificate management needed

   **Verification:**
   ```bash
   make deploy          # builds image, pushes to ECR, provisions App Runner (~2 min to become healthy)
   make smoke-frontend  # polls until the gallery returns HTTP 200
   make open-gallery    # opens the URL in your browser
   ```

3. **Glue + Athena** — Configure a Glue crawler to catalog the S3 bucket. Add an Athena query endpoint that filters by exact label match — a complement to vector search for structured queries.

4. **Claude query rewriting** — Use Bedrock Claude to expand natural-language queries before embedding. For example, `"beach"` → `"sandy beach, ocean waves, coastal scenery, summer sky"`.

5. **DLQ on ingest Lambda** — Add an SQS Dead Letter Queue. Configure a redrive policy so failed ingest invocations (unhandled exceptions after Lambda retries) land in the DLQ for inspection.

6. **moto unit tests** — Write `pytest` tests for both handlers using `moto` to mock S3, Rekognition, Bedrock, and DynamoDB. Test the happy path and key error conditions.

---

## Quick Reference

### Makefile Cheat Sheet

```bash
make install           # uv sync — install Python dependencies
make setup             # terraform init
make package           # build Lambda zips with bundled dependencies
make deploy            # provision infrastructure + export .tf_outputs.env
make upload            # upload IMAGE to S3 (IMAGE ?= test-image.jpg)
make logs-ingest       # tail ingest Lambda CloudWatch logs
make logs-search       # tail search Lambda CloudWatch logs
make wait-opensearch   # poll until OpenSearch collection is ACTIVE
make search QUERY=dog  # call the search API
make smoke-ingest      # poll CloudWatch for "OpenSearch: indexed"
make smoke-search      # assert search returns results
make e2e               # full: deploy → upload → smoke-ingest → search → smoke-search → destroy
make destroy           # terraform destroy + remove .tf_outputs.env
make clean             # remove zips, caches, .tf_outputs.env
```

### Key Terraform CLI Commands

| Command | When to Run |
|---------|-------------|
| `terraform init` | After adding providers/modules or cloning |
| `terraform validate` | After editing `.tf` files — catches syntax errors |
| `terraform plan` | Before every `apply` — review changes |
| `terraform apply` | Create or update infrastructure |
| `terraform output -raw <name>` | Read a single output value (for shell use) |
| `terraform destroy` | Tear down all managed resources |

### S3 Event Structure (abridged)
```json
{
  "Records": [{
    "eventSource": "aws:s3",
    "s3": {
      "bucket": { "name": "photo-gallery-images" },
      "object": { "key": "summer%2Fbeach.jpg", "size": 204800 }
    }
  }]
}
```

### Bedrock Titan Embed Image Request/Response
```python
# Request
body = json.dumps({"inputText": "Beach, Ocean, Summer, Sunny"})

# Response
response = bedrock.invoke_model(modelId="amazon.titan-embed-image-v1", body=body, ...)
embedding = json.loads(response["body"].read())["embedding"]
# embedding is a list of 1024 floats
```

### OpenSearch k-NN Query Structure
```json
{
  "size": 5,
  "query": {
    "knn": {
      "embedding": {
        "vector": [0.123, -0.456, ...],
        "k": 5
      }
    }
  }
}
```

### Key IAM Permissions Summary

| Stage | Service | Action | Resource |
|-------|---------|--------|----------|
| 1 | CloudWatch Logs | `logs:CreateLogGroup/Stream/PutLogEvents` | Lambda log group ARN |
| 1 | S3 | `s3:GetObject` | `${bucket_arn}/*` |
| 2 | Rekognition | `rekognition:DetectLabels` | `*` |
| 3 | DynamoDB | `dynamodb:PutItem`, `dynamodb:UpdateItem` | Table ARN |
| 4 | Bedrock | `bedrock:InvokeModel` | Titan model ARN |
| 5 | OpenSearch Serverless | `aoss:APIAccessAll` | Collection ARN |
| 6 | Bedrock | `bedrock:InvokeModel` | Titan model ARN (search role) |
| 6 | OpenSearch Serverless | `aoss:APIAccessAll` | Collection ARN (search role) |
