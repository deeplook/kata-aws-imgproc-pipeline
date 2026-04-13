variable "s3_bucket_arn" {
  description = "ARN of the S3 image bucket"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 image bucket"
  type        = string
}

variable "table_name" {
  description = "Name of the DynamoDB metadata table"
  type        = string
}

variable "table_arn" {
  description = "ARN of the DynamoDB metadata table"
  type        = string
}

variable "collection_name" {
  description = "Name of the OpenSearch Serverless collection"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}
