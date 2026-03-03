###############################################################################
# Production Environment — marciobolsoni.cloud
# Orchestrates all modules for the production environment.
###############################################################################

terraform {
  required_version = "~> 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # Configured via -backend-config flags in CI/CD
    # bucket         = var.TF_STATE_BUCKET
    # key            = "prod/terraform.tfstate"
    # region         = "us-east-1"
    # dynamodb_table = var.TF_LOCK_TABLE
    # encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "marciobolsoni-cloud"
      Environment = "prod"
      ManagedBy   = "Terraform"
      Repository  = "github.com/marciobolsoni/marciobolsoni.cloud"
    }
  }
}

locals {
  environment = "prod"
  project     = "marciobolsoni-cloud"
}

# ─────────────────────────────────────────────
# KMS Key for Encryption
# ─────────────────────────────────────────────
resource "aws_kms_key" "main" {
  description             = "KMS key for marciobolsoni.cloud production"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name = "${local.project}-${local.environment}-kms"
  }
}

resource "aws_kms_alias" "main" {
  name          = "alias/${local.project}-${local.environment}"
  target_key_id = aws_kms_key.main.key_id
}

# ─────────────────────────────────────────────
# VPC
# ─────────────────────────────────────────────
module "vpc" {
  source = "../../modules/vpc"

  project            = local.project
  environment        = local.environment
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
  enable_nat_gateway = true

  tags = {
    Environment = local.environment
  }
}

# ─────────────────────────────────────────────
# ALB Module
# ─────────────────────────────────────────────
module "alb" {
  source = "../../modules/alb"

  project        = local.project
  environment    = local.environment
  vpc_id         = module.vpc.vpc_id
  public_subnets = module.vpc.public_subnet_ids
  certificate_arn = var.acm_certificate_arn
  kms_key_arn    = aws_kms_key.main.arn

  tags = {
    Environment = local.environment
  }
}

# ─────────────────────────────────────────────
# ECR Repository
# ─────────────────────────────────────────────
resource "aws_ecr_repository" "app" {
  name                 = local.project
  image_tag_mutability = "MUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.main.arn
  }

  tags = {
    Name = "${local.project}-ecr"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 production images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ─────────────────────────────────────────────
# ECS Cluster & Service
# ─────────────────────────────────────────────
module "ecs" {
  source = "../../modules/ecs"

  project               = local.project
  environment           = local.environment
  aws_region            = var.aws_region
  aws_account_id        = data.aws_caller_identity.current.account_id
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  alb_security_group_id = module.alb.security_group_id
  target_group_blue_arn = module.alb.target_group_blue_arn
  ecr_repository_url    = aws_ecr_repository.app.repository_url
  image_tag             = var.image_tag
  kms_key_arn           = aws_kms_key.main.arn
  log_retention_days    = 30
  task_cpu              = 512
  task_memory           = 1024
  container_port        = 3000
  desired_count         = 2
  min_capacity          = 2
  max_capacity          = 10

  tags = {
    Environment = local.environment
  }
}

# ─────────────────────────────────────────────
# CloudWatch Alarms & Dashboard
# ─────────────────────────────────────────────
module "cloudwatch" {
  source = "../../modules/cloudwatch"

  project          = local.project
  environment      = local.environment
  kms_key_arn      = aws_kms_key.main.arn
  alb_arn_suffix   = module.alb.alb_arn_suffix
  ecs_cluster_name = module.ecs.cluster_name
  ecs_service_name = module.ecs.service_name
  min_running_tasks = 1
  alert_emails     = var.alert_emails

  tags = {
    Environment = local.environment
  }
}

# ─────────────────────────────────────────────
# CodeDeploy & CodePipeline
# ─────────────────────────────────────────────
module "codedeploy" {
  source = "../../modules/codedeploy"

  project                  = local.project
  environment              = local.environment
  aws_region               = var.aws_region
  vpc_id                   = module.vpc.vpc_id
  private_subnet_ids       = module.vpc.private_subnet_ids
  ecs_cluster_name         = module.ecs.cluster_name
  ecs_service_name         = module.ecs.service_name
  alb_listener_arn         = module.alb.https_listener_arn
  alb_test_listener_arn    = module.alb.test_listener_arn
  target_group_blue_name   = module.alb.target_group_blue_name
  target_group_green_name  = module.alb.target_group_green_name
  ecr_repository_url       = aws_ecr_repository.app.repository_url
  artifacts_bucket         = aws_s3_bucket.artifacts.id
  kms_key_arn              = aws_kms_key.main.arn
  github_owner             = var.github_owner
  github_repo              = var.github_repo
  github_branch            = "main"
  github_oauth_token       = var.github_oauth_token
  deployment_config_name   = "CodeDeployDefault.ECSCanary10Percent5Minutes"
  termination_wait_minutes = 5
  cloudwatch_alarm_names   = module.cloudwatch.rollback_alarm_names

  tags = {
    Environment = local.environment
  }
}

# ─────────────────────────────────────────────
# S3 Bucket for Artifacts
# ─────────────────────────────────────────────
resource "aws_s3_bucket" "artifacts" {
  bucket        = "${local.project}-${local.environment}-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = {
    Name = "${local.project}-${local.environment}-artifacts"
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─────────────────────────────────────────────
# IAM Role for GitHub Actions OIDC
# ─────────────────────────────────────────────
data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
}

resource "aws_iam_role" "github_actions" {
  name = "${local.project}-${local.environment}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_owner}/${var.github_repo}:*"
        }
      }
    }]
  })

  tags = {
    Name = "${local.project}-${local.environment}-github-actions-role"
  }
}
