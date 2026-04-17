terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

resource "aws_s3_bucket" "images" {
  bucket        = var.bucket_name
  force_destroy = true  # allows destroy even when the bucket contains objects
}

resource "aws_dynamodb_table" "metadata" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "image_key"

  attribute {
    name = "image_key"
    type = "S"
  }
}
