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
  region = var.aws_region

  assume_role {
    role_arn     = "arn:aws:iam::${var.target_account_id}:role/TerraformExecutionRole"
    session_name = "terraform-${var.environment}"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source      = "../../modules/vpc"
  vpc_cidr    = var.vpc_cidr
  environment = var.environment
  az_count    = 2
  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "security_groups" {
  source      = "../../modules/security_groups"
  vpc_id      = module.vpc.vpc_id
  environment = var.environment
  allowed_ssh_cidr = var.allowed_ssh_cidr
  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "ec2" {
  source             = "../../modules/ec2"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
  bastion_sg_id      = module.security_groups.bastion_sg_id
  app_sg_id          = module.security_groups.app_sg_id
  instance_type      = var.instance_type
  key_name           = var.key_name
  environment        = var.environment
  min_size           = var.min_size
  max_size           = var.max_size
  desired_capacity   = var.desired_capacity
  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "rds" {
  source             = "../../modules/rds"
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.security_groups.rds_sg_id]
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  instance_class     = var.db_instance_class
  engine             = "postgres"
  engine_version     = "16.3"
  allocated_storage  = 20
  multi_az           = var.multi_az
  environment        = var.environment
  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "alb" {
  source             = "../../modules/alb"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [module.security_groups.alb_sg_id]
  environment        = var.environment
  certificate_arn    = null
  health_check_path  = "/health"
  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
