terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

locals {
  control_account_id = "380093117861"
}

variable "target_account_id" {
  type        = string
  description = "Target AWS account ID"
}

variable "environment" {
  type        = string
  description = "Environment name (dev/staging/prod)"
}

resource "aws_iam_role" "terraform_execution" {
  name = "TerraformExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.control_account_id}:role/GitHubActionsRole"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "terraform_execution_policy" {
  name = "TerraformExecutionPolicy"
  role = aws_iam_role.terraform_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:*",
          "ecs:*",
          "elasticloadbalancing:*",
          "autoscaling:*",
          "logs:*",
          "cloudwatch:*",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:*",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole",
          "iam:CreateInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:ListInstanceProfiles",
          "iam:ListRoles",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "arn:aws:s3:::tf-state-${local.control_account_id}/env:${var.environment}/*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "terraform_execution" {
  name = "TerraformExecutionInstanceProfile"
  role = aws_iam_role.terraform_execution.name
}
