terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# TODO Stage 1: S3 bucket for image uploads
# Hints:
#   - resource type: aws_s3_bucket
#   - set bucket = var.bucket_name
#   - set force_destroy = true so `terraform destroy` works even with objects inside
resource "aws_s3_bucket" "images" {
  bucket        = var.bucket_name
  force_destroy = true  # allows destroy even when the bucket contains objects
}

# TODO Stage 3: DynamoDB table for image metadata
# Hints:
#   - resource type: aws_dynamodb_table
#   - name = var.table_name
#   - billing_mode = "PAY_PER_REQUEST" (no capacity planning needed)
#   - hash_key = "image_key" (the S3 object key is the natural primary key)
#   - attribute block: name = "image_key", type = "S" (string)
resource "aws_dynamodb_table" "metadata" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "image_key"

  attribute {
    name = "image_key"
    type = "S"
  }
}
