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
        # Stage 1: S3 read
        Action   = "s3:GetObject"
        Effect   = "Allow"
        Resource = "${var.s3_bucket_arn}/*"
      },
      {
        # Stage 2: Rekognition
        Action   = "rekognition:DetectLabels"
        Effect   = "Allow"
        Resource = "*"
      },
      {
        # Stage 3: DynamoDB
        Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
        Effect   = "Allow"
        Resource = var.table_arn
      },
      {
        # Stage 4: Bedrock Titan Embed Image
        Action   = "bedrock:InvokeModel"
        Effect   = "Allow"
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-image-v1"
      },
      {
        # Stage 5: OpenSearch Serverless
        Action   = "aoss:APIAccessAll"
        Effect   = "Allow"
        Resource = aws_opensearchserverless_collection.gallery.arn
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# Lambda — ingest function
# ---------------------------------------------------------------------------

# Stage 5: switched to source_dir to bundle opensearch-py + requests-aws4auth
# Run `make package` before `make deploy` to build lambdas/ingest/package/
data "archive_file" "ingest_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambdas/ingest/package"
  output_path = "${path.module}/../../../lambdas/ingest/handler.zip"
}

resource "aws_lambda_function" "ingest" {
  function_name    = "ingest-lambda"
  role             = aws_iam_role.ingest_exec.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.ingest_zip.output_path
  source_code_hash = data.archive_file.ingest_zip.output_base64sha256
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

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.s3_bucket_arn
}

resource "aws_s3_bucket_notification" "ingest_trigger" {
  bucket = var.s3_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.ingest.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# ---------------------------------------------------------------------------
# OpenSearch Serverless — photo-gallery collection
# ---------------------------------------------------------------------------

resource "aws_opensearchserverless_security_policy" "encryption" {
  name = "${var.collection_name}-encryption"
  type = "encryption"

  policy = jsonencode({
    Rules       = [{ ResourceType = "collection", Resource = ["collection/${var.collection_name}"] }]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  name = "${var.collection_name}-network"
  type = "network"

  policy = jsonencode([{
    Rules = [
      { ResourceType = "collection", Resource = ["collection/${var.collection_name}"] },
      { ResourceType = "dashboard", Resource = ["collection/${var.collection_name}"] },
    ]
    AllowFromPublic = true
  }])
}

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
      },
    ]
    Principal = [
      aws_iam_role.ingest_exec.arn,
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root",
      # TODO Stage 6: add search Lambda role ARN here
    ]
  }])

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
  ]
}

resource "aws_opensearchserverless_collection" "gallery" {
  name = var.collection_name
  type = "VECTORSEARCH"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
    aws_opensearchserverless_access_policy.data_access,
  ]
}
