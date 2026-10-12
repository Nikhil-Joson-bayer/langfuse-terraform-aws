# Langfuse Centralized Observability on AWS (Hub & Spoke Architecture)

[![Terraform](https://img.shields.io/badge/Terraform-%E2%89%A51.14.6-623CE4.svg?logo=terraform)](https://www.terraform.io/)
[![AWS Provider](https://img.shields.io/badge/AWS%20Provider-%E2%89%A55.0%20%3C7.0-F90.svg?logo=amazon-aws)](https://registry.terraform.io/providers/hashicorp/aws/latest)
[![Langfuse](https://img.shields.io/badge/Langfuse-v3.x-000000.svg?logo=langfuse)](https://langfuse.com/)

Centralized LLM observability platform for the **PX CH Parchai Platform** at Bayer. 
Provides unified tracing, evaluations, session replays, and cost monitoring across all platform agents (**CH MAIA**, **Top Loss Card**, and future sub-teams) through **one centralized Langfuse instance** with project-level isolation and zero data leakage.

---

## 1. Architecture Overview

This solution implements a **Centralized Hub-and-Spoke model powered by AWS PrivateLink**:
- **Central Hub**: Deployed in a central observability VPC. Runs Langfuse on **AWS ECS Fargate**, backed by **Aurora Serverless v2 PostgreSQL**, **ElastiCache Redis 7.x**, an internal **Network Load Balancer (NLB)**, and an **AWS VPC Endpoint Service**.
- **Spokes (Agent Teams)**: Any agent running in another VPC (e.g. `ch-px-ai-maia-infra` or future sub-teams) provisions a lightweight **Interface VPC Endpoint** via our `spoke` module. Traffic traverses the private AWS network backbone—no public internet exposure, no VPC peering route conflicts, and zero hub reconfiguration.

```
┌────────────────────────────────────────────────────────────┐
│               Central Observability VPC                    │
│                                                            │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  ECS Fargate                                        │  │
│  │  ├── langfuse-web    (port 3000)                    │  │
│  │  ├── langfuse-worker (background jobs & queues)     │  │
│  │  └── clickhouse      (embedded OLAP analytics)      │  │
│  └───────────────────────────────────────────────────┬─┘  │
│                      ↓                               │     │
│  ┌───────────────────┐   ┌──────────────────┐        │     │
│  │ Aurora Serverless │   │ ElastiCache Redis│        │     │
│  │ v2 (PostgreSQL)   │   │ 7.x (BullMQ)     │        │     │
│  └───────────────────┘   └──────────────────┘        │     │
│                                                       │     │
│  ┌────────────────────────────────────────────────┐  │     │
│  │  Network Load Balancer (NLB)                   │  │     │
│  │  → IP Targets: ECS tasks on TCP port 3000      │  │     │
│  └───────────────────────────┬────────────────────┘  │     │
│                              │                        │     │
│  ┌───────────────────────────▼────────────────────┐  │     │
│  │  VPC Endpoint Service (PrivateLink)            │  │     │
│  │  com.amazonaws.vpce.eu-central-1.vpce-svc-XXXX │  │     │
│  └───────────────────────────┬────────────────────┘  │     │
└──────────────────────────────┼────────────────────────┘     │
                               │  AWS PrivateLink (private)    │
              ┌────────────────┼─────────────────┐
              │                │                 │
   ┌──────────▼─────┐  ┌───────▼────────┐  ┌────▼───────────┐
   │  CH MAIA VPC   │  │ Top Loss VPC   │  │ Future Agent   │
   │  Interface     │  │ Interface      │  │ VPC Interface  │
   │  Endpoint      │  │ Endpoint       │  │ Endpoint       │
   │  10.x.x.x:3000 │  │ 10.y.y.y:3000  │  │ 10.z.z.z:3000  │
   └──────────┬─────┘  └───────┬────────┘  └────┬───────────┘
              │                │                 │
   ┌──────────▼─────┐  ┌───────▼────────┐  ┌────▼───────────┐
   │ MAIA Agent     │  │ Top Loss Agent │  │ Agent C Code   │
   │ LANGFUSE_HOST= │  │ LANGFUSE_HOST= │  │ LANGFUSE_HOST= │
   │ langfuse.      │  │ langfuse.      │  │ langfuse.      │
   │ internal.bayer │  │ internal.bayer │  │ internal.bayer │
   └────────────────┘  └────────────────┘  └────────────────┘
```

### Why NLB Instead of ALB?
AWS PrivateLink **mandates a Network Load Balancer (NLB)** as the endpoint service target. An Application Load Balancer (ALB) cannot act as an endpoint service target. This repository uses an internal NLB directly targeting ECS Fargate task IPs on port 3000.

---

## 2. AWS Services Created & Architectural Roles

| AWS Service | Resource Identifier / Type | Architectural Role |
|---|---|---|
| **AWS ECS Fargate** | `aws_ecs_cluster`, `aws_ecs_task_definition`, `aws_ecs_service` | Serverless container compute running `langfuse-web` (UI/API), `langfuse-worker` (background tasks), and optional embedded `clickhouse` with container health checks and dependencies. |
| **Amazon Aurora Serverless v2** | `aws_rds_cluster`, `aws_rds_cluster_instance`, `aws_db_subnet_group` | PostgreSQL 15.7 engine storing relational data (organizations, projects, users, API keys, prompt versions). Auto-scales between 0.5 and 4.0+ ACUs. |
| **Amazon ElastiCache Redis** | `aws_elasticache_replication_group`, `aws_elasticache_subnet_group`, `aws_elasticache_parameter_group` | Redis 7.1 replication group with `noeviction` maxmemory policy (mandated for BullMQ background queues), transit TLS, and KMS at-rest encryption. |
| **AWS Network Load Balancer** | `aws_lb`, `aws_lb_target_group`, `aws_lb_listener` | Internal NLB load-balancing TCP port 3000 across private subnets; targets Fargate tasks via IP mode with HTTP `/api/public/health` checks. |
| **AWS PrivateLink** | `aws_vpc_endpoint_service`, `aws_vpc_endpoint_service_allowed_principal` | Endpoint service attached to the NLB exposing Langfuse securely to other Bayer VPCs without internet routing or VPC peering. |
| **AWS Secrets Manager** | `aws_secretsmanager_secret`, `aws_secretsmanager_secret_version` | Stores database credentials, Redis connection URL with auth token, application secrets (NextAuth secret, encryption key, salt), and ClickHouse credentials. |
| **AWS KMS** | `aws_kms_key`, `aws_kms_alias` | Customer Managed Key (CMK) providing unified encryption at rest for Aurora, Redis, Secrets Manager, S3, and CloudWatch Logs. |
| **Amazon S3** | `aws_s3_bucket`, `aws_s3_bucket_lifecycle_configuration` | KMS-encrypted bucket for asynchronous batch trace uploads and export artifacts with lifecycle transition rules. |
| **Amazon CloudWatch** | `aws_cloudwatch_log_group` | Encrypted logging for ECS container streams (`web`, `worker`, `clickhouse`) and Redis slow-log delivery. |
| **Amazon Route 53** | `aws_route53_zone`, `aws_route53_record` | Optional Route53 Private Hosted Zone and alias records (`langfuse.internal.bayer` ➔ NLB). Automatically falls back to NLB DNS when unconfigured. |
| **AWS IAM** | `aws_iam_role`, `aws_iam_role_policy` | Scoped least-privilege roles for ECS Task Execution (image pull, secret retrieval, KMS decrypt) and ECS Task Role (S3 read/write, ECS Exec). |

---

## 3. Container Environment Variables & Secrets Reference

### `langfuse-web` Container

| Name | Type | Value / Source | Description |
|---|---|---|---|
| `NODE_ENV` | Variable | `"production"` | Production runtime environment |
| `PORT` | Variable | `"3000"` | HTTP listener port |
| `NEXTAUTH_URL` | Variable | Resolved DNS or NLB DNS | Base URL for NextAuth authentication redirects |
| `LANGFUSE_ENABLE_EXPERIMENTAL_FEATURES` | Variable | `"true"` | Enables feature flags in Langfuse v3 |
| `LANGFUSE_S3_EVENT_UPLOAD_BUCKET` | Variable | S3 Bucket Name | Destination bucket for batch trace uploads |
| `LANGFUSE_S3_EVENT_UPLOAD_REGION` | Variable | AWS Region | Region of the S3 events bucket |
| `TELEMETRY_ENABLED` | Variable | `"false"` | Disables external telemetry to public endpoints |
| `CLICKHOUSE_URL` | Variable | HTTP URL (e.g. `http://127.0.0.1:8123`) | ClickHouse HTTP endpoint for OLAP trace queries |
| `CLICKHOUSE_MIGRATION_URL` | Variable | TCP URL (e.g. `clickhouse://127.0.0.1:9000`) | ClickHouse native TCP migration URL |
| `CLICKHOUSE_USER` | Variable | `"default"` | ClickHouse database username |
| `CLICKHOUSE_DB` | Variable | `"default"` | ClickHouse database name |
| `CLICKHOUSE_CLUSTER_ENABLED` | Variable | `"false"` | Single-node / standalone ClickHouse mode |
| `DATABASE_URL` | **Secret** | Secrets Manager `db-credentials:database_url` | PostgreSQL connection string |
| `REDIS_URL` | **Secret** | Secrets Manager `redis-credentials:redis_url` | TLS Redis connection string with auth token |
| `NEXTAUTH_SECRET` | **Secret** | Secrets Manager `app-secrets:nextauth_secret` | 32-byte secret used to sign NextAuth JWTs |
| `SALT` | **Secret** | Secrets Manager `app-secrets:salt` | Salt for password hashing |
| `ENCRYPTION_KEY` | **Secret** | Secrets Manager `app-secrets:langfuse_encryption_key` | 256-bit hex encryption key |
| `LANGFUSE_ENCRYPTION_KEY` | **Secret** | Secrets Manager `app-secrets:langfuse_encryption_key` | Duplicate alias for encryption key parity |
| `CLICKHOUSE_PASSWORD` | **Secret** | Secrets Manager `clickhouse-credentials:password` | ClickHouse password (if configured) |
| `AUTH_AZURE_AD_*` | **Secret** | Secrets Manager `entra-credentials:*` | Optional Microsoft Entra ID SSO credentials |

### `langfuse-worker` Container
Runs the async BullMQ worker using the identical environment variables and secrets as `langfuse-web`. Configured with `dependsOn = [clickhouse: HEALTHY]` when embedded ClickHouse is active.

### `clickhouse` Container (Optional Embedded)
- **Image**: `clickhouse/clickhouse-server:24.3`
- **Environment**: `CLICKHOUSE_DB=default`, `CLICKHOUSE_USER=default`
- **Health Check**: `wget --no-verbose --tries=1 --spider http://127.0.0.1:8123/ping || exit 1`
- **Ports**: `8123` (HTTP) and `9000` (Native TCP) bound to localhost loopback.

---

## 4. Spoke Onboarding Guide (For Agent Teams)

When onboarding a new agent (e.g. `CH MAIA`, `Top Loss`, or future agents), the agent team adds the `spoke` module to **their existing Terraform repository**.

### Step 1: Add Spoke Terraform Configuration
In the agent's Terraform codebase (e.g. `ch-px-ai-maia-infra`):

```hcl
module "langfuse_spoke" {
  source = "git::https://github.com/bayer-int/terraform-aws-langfuse-central.git//modules/spoke?ref=v1.0.0"

  vpc_id                   = var.vpc_id
  private_subnet_ids       = var.private_subnet_ids
  endpoint_service_name    = "com.amazonaws.vpce.eu-central-1.vpce-svc-0123456789abcdef0"
  agent_security_group_ids = [aws_security_group.agent_task.id]

  # Optional: friendly DNS in your VPC
  dns_zone_id              = aws_route53_zone.agent_internal.zone_id
  dns_record_name          = "langfuse"

  tags = {
    Platform = "PX-CH-Parchai"
    Agent    = "CH-MAIA"
  }
}

output "langfuse_endpoint_dns" {
  description = "DNS endpoint for Langfuse SDK / OTEL exporter"
  value       = module.langfuse_spoke.endpoint_dns
}
```

---

### Step 2: Agent Telemetry Integration

#### Path A: Zero-Code AWS AgentCore OTEL Integration (Recommended)
AgentCore emits OpenTelemetry traces. Langfuse v3 supports OTLP ingestion natively at `/api/public/otel`.
Set these environment variables in your AgentCore container configuration (`agents_config.yml` or Terraform):

```bash
# Point to your VPC Endpoint DNS on port 3000
OTEL_EXPORTER_OTLP_ENDPOINT=http://<spoke-endpoint-dns>:3000/api/public/otel

# Authorization header: Basic base64(LANGFUSE_PUBLIC_KEY:LANGFUSE_SECRET_KEY)
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic <base64-credentials>
```

#### Path B: LangChain / LangGraph CallbackHandler (Python)
For deep LLM-level observability (exact prompts, tool parameters, token usage, latency breakdowns):

```python
import os
from langfuse.callback import CallbackHandler

langfuse_handler = CallbackHandler(
    public_key=os.environ["LANGFUSE_PUBLIC_KEY"],     # From AWS Secrets Manager
    secret_key=os.environ["LANGFUSE_SECRET_KEY"],     # From AWS Secrets Manager
    host=os.environ["LANGFUSE_HOST"],                 # e.g. "http://langfuse.internal.bayer:3000"
    session_id=session_id,
    user_id=user_email,
)

# Pass to your graph / chain execution:
response = graph.invoke(input_payload, config={"callbacks": [langfuse_handler]})
```

---

## 5. Hub Deployment Guide

### AWS Environment Prerequisites

1. **Central Observability VPC Subnets (AZ Spread)**:
   - Aurora Serverless v2 PostgreSQL DB Subnet Groups and the Network Load Balancer strictly require `private_subnet_ids` to contain subnets in at least **TWO distinct Availability Zones** (e.g. `eu-central-1a` and `eu-central-1b`).
2. **Outbound Internet Access (NAT Gateway)**:
   - ECS Fargate tasks run in private subnets with `assign_public_ip = false`. The container images (`langfuse/langfuse:3.22.0`, `langfuse/langfuse-worker:3.22.0`, `clickhouse/clickhouse-server:24.3`) are hosted on public Docker Hub. The private subnets **MUST have an outbound route (0.0.0.0/0) through an AWS NAT Gateway** (or egress proxy) to pull images during deployment.
3. **KMS CMK**:
   - Provide an existing platform KMS CMK ARN via `KMS_KEY_ARN` or leave null to let Terraform provision a dedicated CMK.
4. **Terraform S3 State Backend**:
   - Ensure the S3 state bucket and DynamoDB lock table exist in your target AWS account.

---

### What to Configure in GitHub Settings (For CI/CD & Forked Repos)

When deploying via GitHub Actions, **you do not need a committed `terraform.tfvars` file**. Configure the following in your repository:

Navigate to: **Settings** ➔ **Secrets and variables** ➔ **Actions**

#### 1. Repository Variables (under the "Variables" tab)

| Variable Name | Required? | Default / Example | Description |
|---|---|---|---|
| `VPC_ID` | **Yes** | `vpc-0123456789abcdef0` | Central Observability VPC ID (Service Catalog) |
| `PRIVATE_SUBNET_IDS` | **Yes** | `["subnet-aaa", "subnet-bbb"]` | Subnets in JSON array format (minimum 2 AZs) |
| `AWS_REGION` | Optional | `eu-central-1` | AWS deployment region |
| `STATE_S3_BUCKET` | **Yes** | `terraform-state-<your-account-id>` | S3 bucket for Terraform remote state |
| `STATE_DYNAMODB_TABLE` | Optional | `terraform-locks` | DynamoDB table for Terraform state locking |
| `ALLOWED_PRINCIPALS` | Optional | `[]` | Extra IAM principal ARNs for PrivateLink (current account is always auto-included) |
| `ENABLE_EMBEDDED_CLICKHOUSE` | Optional | `"true"` | Enables embedded single-node ClickHouse on ECS |
| `CLICKHOUSE_URL` | Optional | `""` | External ClickHouse HTTP URL (if not embedded) |
| `CLICKHOUSE_MIGRATION_URL` | Optional | `""` | External ClickHouse TCP URL (if not embedded) |
| `KMS_KEY_ARN` | Optional | `""` | Existing platform KMS CMK ARN (if available) |
| `CREATE_DNS_ZONE` | Optional | `"false"` | Whether to create a Route53 private hosted zone |
| `OWNER` | Optional | `PX-CH-Team` | Custom Owner team tag for all resources |
| `PLATFORM` | Optional | `PX-CH-Parchai` | Custom Platform tag for all resources |

> **Format Tip**: `PRIVATE_SUBNET_IDS` must be formatted as a valid JSON array string: `["subnet-0123...", "subnet-0456..."]`.
> 
> **Why No AWS Account ID Variable?** Terraform dynamically discovers the deploying AWS Account ID at runtime via `data.aws_caller_identity.current.account_id`. The account is automatically bound to S3 buckets, KMS policies, and PrivateLink allowed principals without any manual account ID input. The only place your Account ID is ever used is inside the `AWS_ROLE_ARN` secret and state bucket name.

#### 2. Repository Secrets (under the "Secrets" tab)

| Secret Name | Required? | Example Value | Description |
|---|---|---|---|
| `AWS_ROLE_ARN` | **Yes** | `arn:aws:iam::<your-account-id>:role/github-actions-terraform` | IAM Role for GitHub Actions OIDC authentication |
| `CLICKHOUSE_PASSWORD` | Optional | `your-secure-password` | Password for external ClickHouse (if not embedded) |

---

### Local / CLI Deployment (Alternative)

If testing or applying locally from your workstation:

```bash
cd environments/dev

# 1. Configure remote state backend
cp backend.conf.example backend.conf
# Edit backend.conf with your S3 bucket and DynamoDB table

# 2. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Fill in your vpc_id and private_subnet_ids

# 3. Initialize & Deploy
terraform init -backend-config=backend.conf
terraform plan
terraform apply
```

---

## 6. Trust Boundary & Forking Policy

This hub instance is dedicated to the **PX CH Parchai Platform** agents sharing the same trust domain:
- **Same Hub**: CH MAIA, Top Loss Card, and other PX CH team agents.
- **Separate Teams / Organizations (Forking Instructions)**:
  External Bayer teams requiring independent data governance should **fork this repository**:
  1. Fork `bayer-int/terraform-aws-langfuse-central` to your team's GitHub organization.
  2. In your forked repository's **Settings ➔ Secrets and variables ➔ Actions**, configure your own `VPC_ID`, `PRIVATE_SUBNET_IDS`, and `AWS_ROLE_ARN` as documented in Section 5.
  3. Pushing to `main` will automatically deploy your team's independent hub with physical database and cache isolation.

---

## 7. Preservation of Legacy EKS Manifests

The upstream repository manifests based on Kubernetes (EKS, Helm, Altinity ClickHouse Operator, and AWS Load Balancer Controller) have been preserved in:
`archive/legacy-eks-upstream/`

This ensures that reference configurations for custom evaluators and upstream chart patterns remain accessible without interfering with the ECS Fargate deployment.
