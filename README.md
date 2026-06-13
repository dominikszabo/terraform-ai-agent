# AWS Sigma Terraform Deploy

GitOps infrastructure pipeline deploying VPC/EC2/RDS/ALB stacks across dev/staging/prod AWS accounts.

## Architecture

```
GitHub Actions → OIDC → Control Account (IAM roles + Sigma Lambda)
                             ↓
                    Cross-account role assumption
                             ↓
              Dev/Staging/Prod Target Accounts
              (VPC, EC2, RDS, ALB per environment)
```

- **Orchestrator:** GitHub Actions
- **Auth:** OIDC (no long-lived AWS secrets)
- **Cross-account bridge:** AWS Sigma Lambda (thin IAM assumption)
- **State:** S3 in control account, path-per-env (`env:dev/`, `env:staging/`, `env:prod/`)
- **State locking:** DynamoDB

## Account Structure

| Account | ID | Purpose |
|---|---|---|
| Control | `380093117861` | OIDC, Sigma, S3 state, IAM |
| Dev | `932708079800` | Development environment |
| Staging | `074642417664` | Staging environment |
| Prod | `366985590058` | Production environment |

## Repository Structure

```
.github/workflows/         GitHub Actions pipelines
modules/                   Reusable Terraform modules (vpc, ec2, rds, alb, security_groups)
environments/{dev,staging,prod}/  Per-environment root modules
lambda/sigma_cross_account/  Cross-account IAM bridge Lambda
iam/                       IAM role definitions
backend/                   S3 + DynamoDB bootstrap
docs/                      Design specs and plans
```

## Deployment Flow

1. **Plan:** Trigger `workflow_dispatch` on any environment → manual `terraform plan`
2. **Staging:** Push to `staging` branch → auto `terraform apply` to staging account
3. **Production:** Push to `main` branch → GitHub Environment approval gate → `terraform apply` to prod account

## Prerequisites

1. AWS accounts created (control + 3 target)
2. GitHub repository configured
3. Bootstrap: Apply `backend/s3-backend.tf` in control account
4. Bootstrap: Apply `iam/control-account.tf` in control account
5. Bootstrap: Apply `iam/target-account.tf` in each target account
6. Deploy Sigma Lambda function via `lambda/sigma_cross_account/deploy.sh`

## Setup

### 1. Bootstrap State Storage

```bash
cd backend
terraform init
terraform plan -var="control_account_id=380093117861"
terraform apply -var="control_account_id=380093117861"
```

### 2. Deploy IAM Roles

Control account:
```bash
cd iam
terraform init
terraform plan
terraform apply
```

Each target account (run per account):
```bash
cd iam
terraform plan -var="target_account_id=<ID>" -var="environment=<env>"
terraform apply -var="target_account_id=<ID>" -var="environment=<env>"
```

### 3. Deploy Sigma Lambda

```bash
cd lambda/sigma_cross_account
chmod +x deploy.sh
./deploy.sh
```

### 4. Configure GitHub Environments

Create GitHub Environments (`dev`, `staging`, `prod`) with:
- **prod**: Enable `Required reviewers` protection rule

### 5. Set GitHub OIDC

Configure the OIDC provider in AWS IAM for `token.actions.githubusercontent.com`.

## Security

- OIDC only — no long-lived AWS secrets in GitHub
- Least-privilege IAM — target account roles scoped to Terraform-managed resources
- State encryption at rest (SSE-S3)
- State locking via DynamoDB prevents concurrent applies
- Sigma Lambda validates target account ID against allowlist
- Production requires manual approval via GitHub Environments
