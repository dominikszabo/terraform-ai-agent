# AWS Sigma Terraform Control Node — Design Specification

**Date:** 2026-06-12
**Status:** Draft

---

## 1. Overview

This project establishes a GitOps-based infrastructure deployment pipeline where Terraform configurations live in GitHub and are deployed to AWS via GitHub Actions. A thin AWS Sigma function acts as a cross-account role assumption bridge, enabling the control account to provision resources into isolated target AWS member accounts (dev, staging, prod).

**Guiding Principles:**
- GitHub Actions is the CI/CD orchestrator (not Sigma)
- Sigma is a thin IAM bridge only — no Terraform logic
- All Terraform state is centralized in the control account S3 bucket
- Cross-account access via OIDC-issued temporary credentials — no long-lived secrets

---

## 2. Account Structure

| Account        | Role                                | Resources Created |
|----------------|-------------------------------------|-------------------|
| Control        | OIDC identity, Sigma function, S3 state, IAM roles | None (orchestration only) |
| Dev            | Target environment                  | VPC, EC2, RDS, ALB |
| Staging        | Target environment                  | VPC, EC2, RDS, ALB |
| Prod           | Target environment                  | VPC, EC2, RDS, ALB |

---

## 3. Architecture

```
GitHub                              Control Account                      Target Accounts
┌────────────────┐                 ┌────────────────────────────┐       ┌──────────────────────┐
│ GitHub Repo    │                 │  S3 Bucket (Terraform      │       │  Dev Account         │
│ (PR / Merge)   │                 │  state, path-per-env)      │       │  - VPC               │
└───────┬────────┘                 │                            │       │  - Subnets           │
        │ OIDC                     │  DynamoDB Table            │◄──────│  - EC2 Instances     │
        │                          │  (state locking)           │       │  - RDS Instance      │
        │                          │                            │       │  - ALB               │
        ▼                          │  IAM Role                  │       │  - Security Groups   │
┌────────────────────────┐         │  (trusted: GitHub OIDC +   │       └──────────────────────┘
│  GitHub Actions        │         │   control account)         │
│  Workflows             │         │                            │
│  - terraform plan      ├────────►│  Sigma Function            │
│  - terraform apply     │         │  (cross-account assume)   │
└────────────────────────┘         └────────────────────────────┘

                                                                 ┌──────────────────────┐
                                                                 │  Staging Account     │
                                                                 │  (same resources)    │
                                                                 └──────────────────────┘

                                                                 ┌──────────────────────┐
                                                                 │  Prod Account        │
                                                                 │  (same resources)    │
                                                                 └──────────────────────┘
```

---

## 4. Components

### 4.1 GitHub Actions Workflows

**File:** `.github/workflows/`

#### `terraform-plan.yml` (Manual / on-demand)
- Triggered via `workflow_dispatch`
- Uses OIDC to assume role in control account
- Runs `terraform init` and `terraform plan` against target environment
- Posts plan output as GitHub Actions summary
- State fetched from `s3://tf-state-{env}/`

#### `terraform-apply.yml` (Merge-gated)
- Triggered on push to `staging` or `main` branches
- Uses OIDC to assume role in control account
- Runs `terraform init` and `terraform apply`
- Applies to staging on push to `staging`
- Applies to prod on push to `main`
- `main` branch has GitHub Environment protection rules (manual approval gate)

**OIDC Configuration:**
- GitHub OIDC provider configured in control account
- Role trusted by specific repository: `repo:<org>/<repo>:*`
- Role has `sts:AssumeRoleWithWebIdentity` permission

### 4.2 Sigma Function

**Purpose:** Thin cross-account role assumption bridge. No Terraform logic.

**Input (event payload):**
```json
{
  "target_account_id": "123456789012",
  "target_role_name": "TerraformExecutionRole",
  "session_name": "terraform-dev-apply"
}
```

**Output:**
```json
{
  "access_key_id": "...",
  "secret_access_key": "...",
  "session_token": "...",
  "expiration": "2026-06-12T12:00:00Z"
}
```

**Behavior:**
1. Validate input (check target account ID against allowlist)
2. Assume role in target account using control account credentials
3. Return temporary credentials to caller (GitHub Actions workflow)

**Runtime:** Python 3.x, no external dependencies beyond boto3.

### 4.3 IAM Roles

#### Control Account — `GitHubActionsRole`
- Trusted entities: GitHub OIDC provider
- Permissions: `sts:AssumeRole` on `arn:aws:iam::*:role/TerraformExecutionRole`

#### Target Accounts — `TerraformExecutionRole`
- Trusted entity: Control account `GitHubActionsRole`
- Permissions: Full EC2, RDS, VPC, ELB, IAM (for instance profiles), CloudWatch Logs

### 4.4 Terraform State Storage (S3 in Control Account)

| Bucket                  | Path Prefix        | Environment |
|-------------------------|--------------------|-------------|
| `tf-state-<account-id>` | `env:dev/`         | Dev         |
| `tf-state-<account-id>` | `env:staging/`     | Staging     |
| `tf-state-<account-id>` | `env:prod/`        | Prod        |

- DynamoDB table `tf-state-locks` with partition key `LockID` per environment
- Versioning enabled on S3
- Encryption: SSE-S3 (AES-256)

### 4.5 Target Account Resources (per environment)

| Resource      | Description                                              |
|---------------|----------------------------------------------------------|
| VPC           | CIDR block (e.g., `10.0.0.0/16`), DNS hostnames enabled |
| Subnets       | 2 public + 2 private subnets across AZs                  |
| Internet GW   | Attached to public subnets                               |
| NAT Gateway   | In public subnets for private subnet egress              |
| Route Tables  | Public (IGW), Private (NAT GW)                           |
| Security Groups | EC2 (22/80/443), RDS (3306), ALB (80/443)             |
| EC2 Instances | Bastion host (public) + App servers (private)            |
| RDS Instance  | MySQL/PostgreSQL, Multi-AZ for staging/prod             |
| ALB           | Publicfacing, health checks, target groups               |
| IAM Instance Profile | For EC2 to access S3, Systems Manager              |

---

## 5. Repository Structure

```
terraform-AWS-deploy/
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml
│       ├── terraform-apply-staging.yml
│       └── terraform-apply-prod.yml
├── modules/
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── ec2/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── rds/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── alb/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── backend.tf
│   │   └── terraform.tfvars
│   ├── staging/
│   │   └── (same structure)
│   └── prod/
│       └── (same structure)
├── lambda/
│   └── sigma_cross_account/
│       ├── lambda_function.py
│       └── requirements.txt
├── iam/
│   ├── control-account-roles.tf
│   └── target-account-roles.tf
├── docs/
│   └── superpowers/
│       └── specs/
│           └── 2026-06-12-aws-sigma-terraform-design.md
└── README.md
```

---

## 6. Workflow Behavior

### Deployment Flow

```
Developer opens/updates PR
    │
    ▼
workflow_dispatch → terraform-plan.yml
    │ (OIDC → assume control role)
    │ (terraform init → fetch state from S3)
    │ (terraform plan)
    │ (post output to GitHub Actions summary)
    ▼
Reviewer reviews plan in PR
    │
    ▼
Merge to staging branch
    │
    ▼
terraform-apply-staging.yml auto-triggers
    │ (terraform init → terraform apply)
    │ (creates/updates dev/staging resources)
    ▼
Merge to main branch
    │
    ▼
terraform-apply-prod.yml auto-triggers
    │ (requires GitHub Environment approval for prod)
    ▼
Production resources deployed
```

### Production Gate (Future)

When ready for time-based production promotion:
1. Push to `main` triggers `terraform-apply-prod.yml`
2. GitHub Environment `prod` has `required_reviewers` protection rule
3. Add scheduled EventBridge rule to auto-approve after a specific date/time (separate future module)

---

## 7. Security Considerations

- **No long-lived AWS secrets** in GitHub — OIDC used exclusively
- **Least-privilege IAM** — target account roles scoped to Terraform-managed resources
- **State encryption** at rest (SSE-S3)
- **State locking** via DynamoDB prevents concurrent applies
- **Control account allowlist** in Sigma function — only pre-approved target account IDs can be assumed
- **GitHub OIDC** restricts role assumption to specific repository

---

## 8. Future Phases

| Phase | Description |
|-------|-------------|
| Phase 1 (this design) | Manual/merge-gated apply, OIDC auth, Sigma cross-account bridge, full VPC/EC2/RDS/ALB stack |
| Phase 2 | Drift detection with scheduled `terraform plan` on a cron |
| Phase 3 | Time-based production promotion via EventBridge + Lambda approval gate |
| Phase 4 | Multi-region support within target accounts |

---

## 9. Out of Scope

- Provisioning AWS accounts or Organizations (assumes accounts exist)
- Secret management for application secrets (RDS passwords via Secrets Manager — future)
- Container/EKS workloads
- Terraform Cloud or Atlantis (GitHub Actions used instead)
- Remote state backend in target accounts

---

## 10. Decisions Made

| Decision | Choice |
|----------|--------|
| CI/CD orchestrator | GitHub Actions (not CodePipeline) |
| GitHub → AWS auth | OIDC (not stored secrets) |
| Sigma role | Thin IAM bridge only (no Terraform logic) |
| Terraform state location | S3 in control account, path-per-env |
| Plan trigger | Manual (`workflow_dispatch`) |
| Apply trigger | Push to `staging`/`main` branches |
| Prod gate | GitHub Environment protection rules |
| Target resources | Full stack: VPC, EC2, RDS, ALB |
| VPC strategy | Create new VPC per environment from scratch |