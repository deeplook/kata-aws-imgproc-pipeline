terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# IAM — ingest Lambda execution role
# ---------------------------------------------------------------------------

# TODO Stage 1: IAM role for the ingest Lambda
# Hints:
#   - resource type: aws_iam_role
#   - assume_role_policy allows "lambda.amazonaws.com" to call sts:AssumeRole
resource "aws_iam_role" "ingest_exec" {
  name = "ingest-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# TODO Stage 1: IAM policy for the ingest Lambda
# Build this up incrementally — add one Statement block per stage:
#   Stage 1: logs:CreateLogGroup/Stream/PutLogEvents on the Lambda log group
#   Stage 2: rekognition:DetectLabels on "*"
#   Stage 3: dynamodb:PutItem + dynamodb:UpdateItem on the table ARN
#   Stage 4: bedrock:InvokeModel on the Titan embed model ARN
#   Stage 5: aoss:APIAccessAll on the OpenSearch collection ARN
#            s3:GetObject on "${var.s3_bucket_arn}/*"
resource "aws_iam_role_policy" "ingest_policy" {
  name = "ingest-lambda-policy"
  role = aws_iam_role.ingest_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Stage 1: CloudWatch Logs
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/ingest-lambda:*"
      },
      {
        # Stage 2: rekognition:DetectLabels on "*"
        Action   = "rekognition:DetectLabels"
        Effect   = "Allow"
        Resource = "*"
      },
      {
        # Stage 3: DynamoDB write permissions
        Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
        Effect   = "Allow"
        Resource = var.table_arn
      },
      {
        # Stage 4: Bedrock InvokeModel for Titan Embed Image
        Action   = "bedrock:InvokeModel"
        Effect   = "Allow"
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-image-v1"
      },
      {
        # Stage 5: OpenSearch Serverless data plane access
        Action   = "aoss:APIAccessAll"
        Effect   = "Allow"
        Resource = aws_opensearchserverless_collection.gallery.arn
      },
      {
        # Stage 1: S3 read permission (needed by Rekognition via Lambda role)
        Action   = "s3:GetObject"
        Effect   = "Allow"
        Resource = "${var.s3_bucket_arn}/*"
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# Lambda — ingest function
# ---------------------------------------------------------------------------

# TODO Stage 1: package the ingest handler
# Hints:
#   - resource type: archive_file (data source, not resource)
#   - type = "zip"
#   - After Stage 5, use source_dir pointing to the pre-built package directory
#     (built by `make package`) instead of a single source_file
data "archive_file" "ingest_zip" {
  type        = "zip"
  source_file = "${path.module}/../../../lambdas/ingest/handler.py"
  output_path = "${path.module}/../../../lambdas/ingest/handler.zip"
}

# TODO Stage 1: Lambda function resource
# Hints:
#   - function_name: "ingest-lambda"
#   - handler: "handler.lambda_handler"
#   - runtime: "python3.12"
#   - role: aws_iam_role.ingest_exec.arn
#   - filename: data.archive_file.ingest_zip.output_path
#   - source_code_hash: data.archive_file.ingest_zip.output_base64sha256
#   - timeout: 60 (seconds) — Rekognition + Bedrock + OpenSearch calls take time
#   - environment variables: TABLE_NAME, OPENSEARCH_ENDPOINT, COLLECTION_NAME, AWS_REGION_NAME
resource "aws_lambda_function" "ingest" {
  function_name    = "ingest-lambda"
  role             = "???" # TODO Stage 1: aws_iam_role.ingest_exec.arn
  handler          = "???" # TODO Stage 1: "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = "???" # TODO Stage 1: data.archive_file.ingest_zip.output_path
  source_code_hash = "???" # TODO Stage 1: data.archive_file.ingest_zip.output_base64sha256
  timeout          = 60

  environment {
    variables = {
      TABLE_NAME          = var.table_name
      OPENSEARCH_ENDPOINT = aws_opensearchserverless_collection.gallery.collection_endpoint
      COLLECTION_NAME     = var.collection_name
      AWS_REGION_NAME     = var.aws_region
    }
  }
}

# TODO Stage 1: allow S3 to invoke the ingest Lambda
# Hints:
#   - resource type: aws_lambda_permission
#   - statement_id = "AllowS3Invoke"
#   - action = "lambda:InvokeFunction"
#   - principal = "s3.amazonaws.com"
#   - source_arn = var.s3_bucket_arn
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "???" # TODO Stage 1: var.s3_bucket_arn
}

# TODO Stage 1: S3 bucket notification to trigger ingest Lambda on ObjectCreated
# Hints:
#   - resource type: aws_s3_bucket_notification
#   - bucket = var.s3_bucket_name (use the bucket ID/name, not ARN)
#   - events = ["s3:ObjectCreated:*"]
#   - lambda_function_arn = aws_lambda_function.ingest.arn
#   - depends_on = [aws_lambda_permission.allow_s3] — S3 needs the permission first
resource "aws_s3_bucket_notification" "ingest_trigger" {
  bucket = "???" # TODO Stage 1: var.s3_bucket_name

  lambda_function {
    lambda_function_arn = "???" # TODO Stage 1: aws_lambda_function.ingest.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# ---------------------------------------------------------------------------
# OpenSearch Serverless — photo-gallery collection
# ---------------------------------------------------------------------------

# TODO Stage 5: OpenSearch Serverless encryption policy (required before collection)
# Hints:
#   - resource type: aws_opensearchserverless_security_policy
#   - type = "encryption"
#   - policy: JSON with Rules targeting the collection by name
resource "aws_opensearchserverless_security_policy" "encryption" {
  name = "${var.collection_name}-encryption"
  type = "encryption"

  policy = jsonencode({
    Rules = [{
      ResourceType = "collection"
      Resource     = ["collection/${var.collection_name}"]
    }]
    AWSOwnedKey = true # TODO Stage 5: true means AWS-managed key (simplest option)
  })
}

# TODO Stage 5: OpenSearch Serverless network policy (required for data plane access)
# Hints:
#   - resource type: aws_opensearchserverless_security_policy
#   - type = "network"
#   - AllowFromPublic = true for simplicity in this kata
resource "aws_opensearchserverless_security_policy" "network" {
  name = "${var.collection_name}-network"
  type = "network"

  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${var.collection_name}"]
      },
      {
        ResourceType = "dashboard"
        Resource     = ["collection/${var.collection_name}"]
      }
    ]
    AllowFromPublic = true # TODO Stage 5: set to true for kata simplicity
  }])
}

# TODO Stage 5: OpenSearch Serverless data access policy
# Hints:
#   - resource type: aws_opensearchserverless_access_policy
#   - type = "data"
#   - grants ingest Lambda role + current caller full CRUD on collection and indices
resource "aws_opensearchserverless_access_policy" "data_access" {
  name = "${var.collection_name}-data-access"
  type = "data"

  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${var.collection_name}"]
        Permission   = ["aoss:CreateCollectionItems", "aoss:UpdateCollectionItems", "aoss:DescribeCollectionItems"]
      },
      {
        ResourceType = "index"
        Resource     = ["index/${var.collection_name}/*"]
        Permission   = ["aoss:CreateIndex", "aoss:UpdateIndex", "aoss:DescribeIndex", "aoss:ReadDocument", "aoss:WriteDocument"]
      }
    ]
    Principal = [
      aws_iam_role.ingest_exec.arn,
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" # TODO Stage 5: also grant the caller for manual inspection
    ]
  }])

  depends_on = [aws_opensearchserverless_security_policy.encryption, aws_opensearchserverless_security_policy.network]
}

# TODO Stage 5: OpenSearch Serverless collection
# Hints:
#   - resource type: aws_opensearchserverless_collection
#   - type = "VECTORSEARCH"
#   - depends_on the three policies above
resource "aws_opensearchserverless_collection" "gallery" {
  name = var.collection_name
  type = "VECTORSEARCH"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
    aws_opensearchserverless_access_policy.data_access,
  ]
}
