terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

# ---------------------------------------------------------------------------
# ECR — container registry for the gallery web app image
# ---------------------------------------------------------------------------

# TODO Stage 8: ECR repository for the gallery Docker image
# Hints:
#   - resource type: aws_ecr_repository
#   - name: "${var.collection_name}-gallery"
#   - image_tag_mutability = "MUTABLE"
#   - force_delete = true (allows destroy even when images are present)
resource "aws_ecr_repository" "gallery" {
  name                 = "${var.collection_name}-gallery"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# TODO Stage 8: build and push the Docker image to ECR on every apply
# This null_resource runs a local-exec shell script to:
#   1. Get an ECR login token with `aws ecr get-login-password`
#   2. Write credentials to a temp DOCKER_CONFIG dir (avoids macOS keychain errors)
#   3. Build the image with --platform linux/amd64 (App Runner requires x86_64)
#   4. Push to ECR
# The triggers block re-runs the build when Dockerfile, main.py, or pyproject.toml change.
resource "null_resource" "push_image" {
  depends_on = [aws_ecr_repository.gallery]

  triggers = {
    dockerfile = filemd5("${path.module}/../../../app/Dockerfile")
    app        = filemd5("${path.module}/../../../app/main.py")
    pyproject  = filemd5("${path.module}/../../../app/pyproject.toml")
  }

  provisioner "local-exec" {
    command = <<-EOF
      TMPCONFIG=$(mktemp -d)
      ECR_URL="${aws_ecr_repository.gallery.repository_url}"
      ECR_TOKEN=$(aws ecr get-login-password --region ${var.aws_region})
      ECR_AUTH=$(printf 'AWS:%s' "$ECR_TOKEN" | base64 | tr -d '\n')
      printf '{"auths":{"%s":{"auth":"%s"}}}' "$ECR_URL" "$ECR_AUTH" > "$TMPCONFIG/config.json"
      DOCKER_CONFIG="$TMPCONFIG" docker build --platform linux/amd64 \
        -t "$ECR_URL:latest" \
        ${path.module}/../../../app
      DOCKER_CONFIG="$TMPCONFIG" docker push "$ECR_URL:latest"
    EOF
  }
}

# ---------------------------------------------------------------------------
# IAM — App Runner access role (ECR image pull)
# ---------------------------------------------------------------------------

# TODO Stage 8: IAM role assumed by the App Runner control plane to pull ECR images
# Hints:
#   - trust principal: "build.apprunner.amazonaws.com"
#   - attach managed policy: arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess
resource "aws_iam_role" "apprunner_access" {
  name = "apprunner-ecr-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "build.apprunner.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "apprunner_ecr" {
  role       = aws_iam_role.apprunner_access.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

# ---------------------------------------------------------------------------
# IAM — App Runner instance role (runtime AWS API access)
# ---------------------------------------------------------------------------

# TODO Stage 8: IAM role assumed by running containers to call AWS APIs
# Hints:
#   - trust principal: "tasks.apprunner.amazonaws.com"  (different from the access role!)
#   - grant s3:PutObject + s3:GetObject on "${var.s3_bucket_arn}/*"
#   - grant rekognition:DetectLabels on "*"
resource "aws_iam_role" "apprunner_instance" {
  name = "apprunner-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "tasks.apprunner.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "apprunner_s3" {
  name = "apprunner-s3-policy"
  role = aws_iam_role.apprunner_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetObject"]
      Resource = "${var.s3_bucket_arn}/*"
    }]
  })
}

resource "aws_iam_role_policy" "apprunner_rekognition" {
  name = "apprunner-rekognition-policy"
  role = aws_iam_role.apprunner_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "rekognition:DetectLabels"
      Resource = "*"
    }]
  })
}

# ---------------------------------------------------------------------------
# App Runner — gallery service
# ---------------------------------------------------------------------------

# TODO Stage 8: App Runner service
# Hints:
#   - depends_on = [null_resource.push_image] so the image is pushed before the service is created
#   - image_identifier: "${aws_ecr_repository.gallery.repository_url}:latest"
#   - image_repository_type: "ECR"
#   - port: "8080"
#   - runtime_environment_variables: S3_BUCKET, SEARCH_API_URL, AWS_REGION_NAME
#   - access_role_arn: aws_iam_role.apprunner_access.arn  (ECR pull)
#   - instance_role_arn: aws_iam_role.apprunner_instance.arn  (runtime AWS calls)
#   - cpu = "256", memory = "512"  (minimum tier — sufficient for the kata)
#   - auto_deployments_enabled = false
resource "aws_apprunner_service" "gallery" {
  depends_on   = [null_resource.push_image]
  service_name = "${var.collection_name}-gallery"

  source_configuration {
    image_repository {
      image_configuration {
        port = "8080"
        runtime_environment_variables = {
          S3_BUCKET       = var.s3_bucket_name
          SEARCH_API_URL  = var.search_api_url
          AWS_REGION_NAME = var.aws_region
        }
      }
      image_identifier      = "${aws_ecr_repository.gallery.repository_url}:latest"
      image_repository_type = "ECR"
    }
    authentication_configuration {
      access_role_arn = aws_iam_role.apprunner_access.arn
    }
    auto_deployments_enabled = false
  }

  instance_configuration {
    instance_role_arn = aws_iam_role.apprunner_instance.arn
    cpu               = "256"
    memory            = "512"
  }
}
