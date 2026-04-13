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
# IAM — search Lambda execution role
# ---------------------------------------------------------------------------

resource "aws_iam_role" "search_exec" {
  name = "search-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "search_policy" {
  name = "search-lambda-policy"
  role = aws_iam_role.search_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/search-lambda:*"
      },
      {
        Action   = "bedrock:InvokeModel"
        Effect   = "Allow"
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-image-v1"
      },
      {
        Action   = "aoss:APIAccessAll"
        Effect   = "Allow"
        Resource = var.collection_arn
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# OpenSearch data access policy for the search role
# (separate from the ingest policy to avoid a circular dependency)
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Lambda — search function
# ---------------------------------------------------------------------------

data "archive_file" "search_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambdas/search/package"
  output_path = "${path.module}/../../../lambdas/search/handler.zip"
}

resource "aws_lambda_function" "search" {
  function_name    = "search-lambda"
  role             = aws_iam_role.search_exec.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.search_zip.output_path
  source_code_hash = data.archive_file.search_zip.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      OPENSEARCH_ENDPOINT = var.opensearch_endpoint
      COLLECTION_NAME     = var.collection_name
      AWS_REGION_NAME     = var.aws_region
    }
  }
}

# ---------------------------------------------------------------------------
# API Gateway HTTP API
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "search_api" {
  name          = "photo-gallery-search-api"
  protocol_type = "HTTP"
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.search.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.search_api.execution_arn}/*/*"
}

resource "aws_apigatewayv2_integration" "search_integration" {
  api_id                 = aws_apigatewayv2_api.search_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.search.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "search_route" {
  api_id    = aws_apigatewayv2_api.search_api.id
  route_key = "GET /search"
  target    = "integrations/${aws_apigatewayv2_integration.search_integration.id}"
}

# TODO Stage 8: add GET /count route (reuses the same Lambda integration as GET /search)
# resource "aws_apigatewayv2_route" "count_route" {
#   api_id    = aws_apigatewayv2_api.search_api.id
#   route_key = "GET /count"
#   target    = "integrations/${aws_apigatewayv2_integration.search_integration.id}"
# }

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.search_api.id
  name        = "$default"
  auto_deploy = true
}
