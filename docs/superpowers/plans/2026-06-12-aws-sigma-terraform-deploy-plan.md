# AWS Sigma Terraform Deploy — Implementation Plan

**Date:** 2026-06-12
**Status:** Draft
**Based on:** `docs/superpowers/specs/2026-06-12-aws-sigma-terraform-design.md`

---

## Overview

Build a GitOps infrastructure pipeline: GitHub Actions + AWS Sigma (thin cross-account IAM bridge) + Terraform, deploying full-stack VPC/EC2/RDS/ALB across dev/staging/prod AWS accounts.

**Key principles:**
- GitHub Actions is the orchestrator — Sigma is a thin IAM bridge only
- OIDC auth — no long-lived AWS secrets
- S3 state in control account, path-per-env
- GitHub Environment protection rules for prod gate

---

## Phase Breakdown

### Phase 0: Foundation & Bootstrapping
Setup the project structure, local dev tooling, and initial git repo.

### Phase 1: Core Infrastructure (Control Account)
IAM roles, S3 backend, DynamoDB state locking — the plumbing that everything depends on.

### Phase 2: Terraform Modules
Shared reusable modules for VPC, EC2, RDS, ALB.

### Phase 3: Environment Configurations
Per-environment root modules (dev/staging/prod) with backend config, variables, tfvars.

### Phase 4: Sigma Function
Thin Python Lambda for cross-account role assumption bridge.

### Phase 5: GitHub Actions Workflows
CI/CD pipelines: terraform plan (manual), terraform apply (merge-gated) for staging and prod.

### Phase 6: Verification & Documentation
End-to-end testing, README, closing the loop.

---

## File Inventory (to be created)

```
.github/
  workflows/
    terraform-plan.yml
    terraform-apply-staging.yml
    terraform-apply-prod.yml
modules/
  vpc/
    main.tf
    variables.tf
    outputs.tf
  ec2/
    main.tf
    variables.tf
    outputs.tf
  rds/
    main.tf
    variables.tf
    outputs.tf
  alb/
    main.tf
    variables.tf
    outputs.tf
  security_groups/
    main.tf
    variables.tf
    outputs.tf
environments/
  dev/
    main.tf
    variables.tf
    backend.tf
    terraform.tfvars
  staging/
    main.tf
    variables.tf
    backend.tf
    terraform.tfvars
  prod/
    main.tf
    variables.tf
    backend.tf
    terraform.tfvars
lambda/
  sigma_cross_account/
    lambda_function.py
    requirements.txt
    deploy.sh
iam/
  control-account.tf       (applied in control account)
  target-account.tf        (applied in each target account)
backend/
  s3-backend.tf            (applied in control account to create S3 + DynamoDB)
.gitignore
README.md
```

---

## Phase 0: Foundation & Bootstrapping

### Steps

1. **Initialize git repo**
   ```
   cd /Users/dominikszabo/Projects/terraform-AWS-deploy
   git init
   ```

2. **Create `.gitignore`**
   - Ignore: `.terraform/`, `*.tfstate`, `*.tfstate.backup`, `*.tfvars.local`, `*.tfvars.local.json`, crash.log, override.tf, override.tf.json, `.terraform.lock.hcl`, `venv/`, `__pycache__/`

3. **Create directory structure**
   ```
   mkdir -p .github/workflows
   mkdir -p modules/{vpc,ec2,rds,alb,security_groups}
   mkdir -p environments/{dev,staging,prod}
   mkdir -p lambda/sigma_cross_account
   mkdir -p iam
   mkdir -p backend
   ```

---

## Phase 1: Core Infrastructure (Control Account)

Terraform configurations applied manually in the control account to bootstrap the pipeline.

### 1.1 S3 Backend (`backend/s3-backend.tf`)

**Purpose:** Create S3 bucket for state storage + DynamoDB table for state locking in the control account.

Resources:
- `aws_s3_bucket` — `tf-state-{control_account_id}` with versioning, SSE-S3 encryption, `block_public_access`
- `aws_s3_bucket_versioning` — enabled
- `aws_s3_bucket_server_side_encryption_configuration` — AES-256
- `aws_s3_bucket_public_access_block` — block all
- `aws_dynamodb_table` — `tf-state-locks` with `LockID` (string) as partition key, billing mode `PAY_PER_REQUEST`

**State:** This config lives in `backend/` and uses local state (bootstrapped manually).

**Outputs:** Bucket ARN, DynamoDB table name.

### 1.2 IAM: Control Account Roles (`iam/control-account.tf`)

**Purpose:** Create the `GitHubActionsRole` that GitHub Actions assumes via OIDC.

Resources:
- `aws_iam_openid_connect_provider` — GitHub OIDC provider (`token.actions.githubusercontent.com`, thumbprint list)
- `aws_iam_role` — `GitHubActionsRole` with assume role policy trusting the OIDC provider (restricted to repo)
- `aws_iam_role_policy` — attached to `GitHubActionsRole`:
  - `sts:AssumeRole` on `arn:aws:iam::*:role/TerraformExecutionRole`
  - `s3:GetObject`/`s3:PutObject` on `arn:aws:s3:::tf-state-*`
  - `dynamodb:GetItem`/`dynamodb:PutItem`/`dynamodb:DeleteItem` on `tf-state-locks`
  - `lambda:InvokeFunction` on the Sigma function

**State:** This config is applied manually in the control account (can use same S3 backend from 1.1).

**Variables needed:** `control_account_id`, `github_org`, `github_repo`, `sigma_function_name`.

### 1.3 IAM: Target Account Roles (`iam/target-account.tf`)

**Purpose:** Create `TerraformExecutionRole` in each target account.

Resources:
- `aws_iam_role` — `TerraformExecutionRole` trusted by `arn:aws:iam::{control_account_id}:role/GitHubActionsRole`
- `aws_iam_role_policy_attachments` (or inline policy):
  - `ec2:*`, `rds:*`, `ecs:*`, `elasticloadbalancing:*`, `autoscaling:*`, `logs:*`, `iam:PassRole`, `iam:CreateInstanceProfile`, `iam:AddRoleToInstanceProfile`
- `aws_iam_instance_profile` — for EC2 instances

**State:** Applied per target account (separate apply, separate state or local state).

**Variables:** `control_account_id`, `environment_name`.

---

## Phase 2: Terraform Modules

All modules follow the convention: `main.tf`, `variables.tf`, `outputs.tf`. No provider configuration inside modules.

### 2.1 VPC Module (`modules/vpc/`)

| Resource | Details |
|---|---|
| `aws_vpc` | CIDR from variable, `enable_dns_support`, `enable_dns_hostnames` |
| `aws_subnet` | `public` and `private` — count based on `var.az_count`, each in a different AZ |
| `aws_internet_gateway` | Attached to VPC |
| `aws_eip` | One per NAT Gateway |
| `aws_nat_gateway` | One per public subnet |
| `aws_route_table` | One public (IGW), one private (NAT GW) per AZ |
| `aws_route_table_association` | Each subnet associated with its route table |
| `aws_flow_log` | Optional VPC flow logs to CloudWatch (configurable) |

**Variables:** `vpc_cidr`, `environment`, `az_count` (default 2), `public_subnet_cidrs`, `private_subnet_cidrs`, `enable_flow_logs` (default false), `tags`.

**Outputs:** `vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `nat_gateway_ids`.

### 2.2 Security Groups Module (`modules/security_groups/`)

| Resource | Details |
|---|---|
| `aws_security_group` | One per resource: `bastion`, `app_server`, `rds`, `alb` |
| `aws_security_group_rule` | Bastion: SSH from trusted CIDR |
| | App: HTTP/80, HTTPS/443 from ALB SG; SSH from bastion SG |
| | RDS: 3306 from app server SG |
| | ALB: 80/443 from 0.0.0.0/0 |

**Variables:** `vpc_id`, `environment`, `allowed_ssh_cidr`, `tags`.

**Outputs:** `bastion_sg_id`, `app_sg_id`, `rds_sg_id`, `alb_sg_id`.

### 2.3 EC2 Module (`modules/ec2/`)

| Resource | Details |
|---|---|
| `aws_instance` | Bastion in public subnet (or via SSM), app servers in private subnet |
| `aws_launch_template` | For app server auto scaling |
| `aws_autoscaling_group` | App servers across private subnets |
| `aws_iam_instance_profile` | Attached to instances for S3/SSM access |
| `aws_lb_target_group_attachment` | Register instances with ALB target group |

**Variables:** `vpc_id`, `subnet_ids`, `security_group_ids`, `instance_type`, `key_name` (optional), `environment`, `min_size`/`max_size`/`desired_capacity`, `tags`.

**Outputs:** `bastion_id`, `asg_name`, `instance_profile_arn`.

### 2.4 RDS Module (`modules/rds/`)

| Resource | Details |
|---|---|
| `aws_db_instance` | MySQL/PostgreSQL, Multi-AZ for staging/prod, single-AZ for dev |
| `aws_db_subnet_group` | Spans private subnets |
| `aws_security_group_rule` | Allow app server SG access |
| `aws_db_parameter_group` | Optional custom params |

**Variables:** `subnet_ids`, `security_group_ids`, `db_name`, `db_username`, `db_password` (Secrets Manager reference), `instance_class`, `engine`, `engine_version`, `allocated_storage`, `multi_az`, `environment`, `tags`.

**Outputs:** `rds_endpoint`, `rds_arn`.

### 2.5 ALB Module (`modules/alb/`)

| Resource | Details |
|---|---|
| `aws_lb` | Internet-facing, spans public subnets |
| `aws_lb_target_group` | HTTP/80, health check on `/health` |
| `aws_lb_listener` | HTTP:80 (redirect to HTTPS) + HTTPS:443 (forward to target group) |
| `aws_lb_listener_certificate` | ACM certificate ARN (optional, from variable) |

**Variables:** `vpc_id`, `subnet_ids`, `security_group_ids`, `environment`, `certificate_arn` (optional), `tags`.

**Outputs:** `alb_dns_name`, `alb_zone_id`, `target_group_arn`.

---

## Phase 3: Environment Configurations

Per-environment root modules that compose the modules together.

### Structure (each environment: `environments/{dev,staging,prod}/`)

- **`backend.tf`** — S3 backend config (different key per env: `env:dev/terraform.tfstate`)
  ```hcl
  backend "s3" {
    bucket         = "tf-state-{control_account_id}"
    key            = "env:${var.environment}/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tf-state-locks"
    encrypt        = true
  }
  ```

- **`main.tf`** — Terraform root module composing all modules:
  - Provider configuration with `assume_role` to the target account `TerraformExecutionRole`
  - Module calls: `vpc`, `security_groups`, `ec2`, `rds`, `alb`
  - Pass outputs between modules (e.g., `vpc_id` → security groups, subnet IDs → EC2/RDS/ALB)

- **`variables.tf`** — Per-environment variables

- **`terraform.tfvars`** — Environment-specific values:
  - `env/dev`: `vpc_cidr = "10.0.0.0/16"`, smaller instances, single-AZ RDS
  - `env/staging`: `vpc_cidr = "10.1.0.0/16"`, medium instances, multi-AZ RDS
  - `env/prod`: `vpc_cidr = "10.2.0.0/16"`, larger instances, multi-AZ RDS, `min_size = 2`

### Provider Assumption Pattern

```hcl
provider "aws" {
  region = var.aws_region
  assume_role {
    role_arn     = "arn:aws:iam::${var.target_account_id}:role/TerraformExecutionRole"
    session_name = "terraform-${var.environment}"
  }
}
```

---

## Phase 4: Sigma Function

### 4.1 Lambda Function (`lambda/sigma_cross_account/lambda_function.py`)

**Logic:**
1. Receive event: `{ "target_account_id", "target_role_name", "session_name" }`
2. Validate `target_account_id` against an allowlist (environment variable `ALLOWED_ACCOUNT_IDS`)
3. Call `sts:AssumeRole` on `arn:aws:iam::{target_account_id}:role/{target_role_name}`
4. Return `{ "access_key_id", "secret_access_key", "session_token", "expiration" }`
5. Error handling: invalid account → 403, failed assume → 500

**Runtime:** Python 3.12  
**Dependencies:** None beyond boto3 (Lambda SDK)

### 4.2 Deploy Script (`lambda/sigma_cross_account/deploy.sh`)

Zip and deploy the Lambda function to the control account.

### 4.3 Lambda IAM Policy (in `iam/control-account.tf`)

- `sts:AssumeRole` on target account `TerraformExecutionRole`s
- `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`

---

## Phase 5: GitHub Actions Workflows

### 5.1 `terraform-plan.yml` (`workflow_dispatch`)

```yaml
name: Terraform Plan

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        type: choice
        options: [dev, staging, prod]

jobs:
  plan:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::{control_account_id}:role/GitHubActionsRole
          aws-region: us-east-1
      - name: Assume target account role via Sigma
        run: |
          CREDS=$(aws lambda invoke ... sigma_cross_account ...)
          export AWS_ACCESS_KEY_ID=...
          export AWS_SECRET_ACCESS_KEY=...
          export AWS_SESSION_TOKEN=...
      - name: Terraform Init & Plan
        working-directory: environments/${{ inputs.environment }}
        run: |
          terraform init
          terraform plan -out=tfplan
      - name: Upload plan artifact
        uses: actions/upload-artifact@v4
        with:
          name: tfplan
          path: environments/${{ inputs.environment }}/tfplan
```

### 5.2 `terraform-apply-staging.yml` (push to `staging`)

Same as plan but:
- Trigger: `push: branches: [staging]`
- Skips plan step (or uses saved plan)
- Runs `terraform apply`

**Edge case:** If `environments/staging/**` changes, only then run.

### 5.3 `terraform-apply-prod.yml` (push to `main`)

Same as staging but:
- Trigger: `push: branches: [main]`
- `environment: prod` — GitHub Environment with `required_reviewers`
- `paths: environments/prod/**`

**Prod Gate:** GitHub Environment protection rules require manual approval.

---

## Phase 6: Verification & Documentation

### 6.1 Local Verification (pre-commit)
- `terraform fmt --recursive` check
- `terraform validate` on all environments
- `tflint` if available

### 6.2 End-to-End Test
1. Run `terraform plan` for `dev` (simulate via `workflow_dispatch`)
2. Review plan output
3. Merge to `staging` branch → verify auto-apply
4. Verify resources created in dev account
5. `terraform destroy` dev environment
6. Merge to `main` → verify prod gate requires approval

### 6.3 README
- Architecture overview (with diagram)
- Setup instructions (AWS account IDs, OIDC provider setup)
- How to deploy (branch strategy)
- Security notes

---

## Implementation Order (Dependency Chain)

```
Phase 0 (git init + structure)
  │
  ▼
Phase 1.1 (S3 backend) ─── bootstraps state storage
  │
  ▼
Phase 1.2 + 1.3 (IAM roles) ─── enables auth
  │
  ▼
Phase 2 (Modules) ─── reusable building blocks
  │
  ▼
Phase 3 (Environments) ─── composes modules per env
  │
  ▼
Phase 4 (Sigma) ─── cross-account bridge
  │
  ▼
Phase 5 (Workflows) ─── automation + CI/CD
  │
  ▼
Phase 6 (Verification + docs)
```

---

## Files to Create (Summary)

| File | Purpose |
|---|---|
| `.gitignore` | Ignore terraform/lambda artifacts |
| `backend/s3-backend.tf` | S3 + DynamoDB in control account |
| `iam/control-account.tf` | GitHubActionsRole + OIDC provider + Lambda policy |
| `iam/target-account.tf` | TerraformExecutionRole per target account |
| `modules/vpc/*.tf` | VPC + subnets + gateways + routing |
| `modules/security_groups/*.tf` | Security groups for all resources |
| `modules/ec2/*.tf` | Bastion + ASG app servers |
| `modules/rds/*.tf` | RDS instance |
| `modules/alb/*.tf` | ALB + target groups + listeners |
| `environments/{dev,staging,prod}/**/*.tf` | Root modules |
| `lambda/sigma_cross_account/lambda_function.py` | Cross-account bridge |
| `lambda/sigma_cross_account/requirements.txt` | (empty, boto3 built-in) |
| `lambda/sigma_cross_account/deploy.sh` | Zip + deploy script |
| `.github/workflows/terraform-plan.yml` | Manual plan workflow |
| `.github/workflows/terraform-apply-staging.yml` | Staging auto-apply |
| `.github/workflows/terraform-apply-prod.yml` | Prod gated apply |
| `README.md` | Project documentation |

---

## Answered Configuration

| Parameter | Value |
|---|---|
| Control Account ID | `380093117861` |
| Dev Account ID | `932708079800` |
| Staging Account ID | `074642417664` |
| Prod Account ID | `366985590058` |
| GitHub Org | `dominikszabo` |
| GitHub Repo | `terraform-ai-agent` |
| AWS Region | `us-east-2` (Ohio) |
| RDS Engine | PostgreSQL |
| SSH Key Name | `AWS-SSH` |
| Bastion Access | SSH key (not SSM) |
