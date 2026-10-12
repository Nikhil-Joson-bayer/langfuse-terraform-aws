# Langfuse Centralized Observability — New Repo Project Brief

> **Purpose of this file**: Complete context document for starting a fresh Cursor conversation
> in the new `terraform-aws-langfuse-central` repository. Read this fully before writing any code.
> Do NOT re-ask the user to explain the background — all context is here.

---

## 1. Who & Why

**Owner**: PX CH team at Bayer (same team behind `bayer-int/ch-px-ai-maia-infra`)

**Platform**: **PX CH Parchai Platform** — an umbrella AI orchestration platform on AWS.
It currently hosts:
- **CH MAIA** — multi-agent manufacturing AI assistant (IRIS + MES + Databricks data)
- **Top Loss Card** — analytics dashboard agent

More agents will be added over time by different engineering sub-teams, potentially in
**separate VPCs and separate Terraform state files**. Today they share one VPC; tomorrow
they may not.

**Goal**: A **single, centralized Langfuse deployment** that gives the whole platform
observability — traces, sessions, evaluations, costs — with **one project per agent** in
the Langfuse sidebar. No per-agent redeployment of Langfuse. No data leakage between projects.

---

## 2. Decision Already Made — Architecture

**Option 2: Centralized Hub via AWS PrivateLink** was chosen (not per-team deploys).

### Why

| Concern | Answer |
|---|---|
| Multi-agent sidebar | Langfuse natively supports **Organizations → Projects** — sidebar project switcher is built-in |
| Data isolation | Each agent = one Langfuse Project with its own API key pair |
| Cost | One Aurora + one ECS cluster shared across all agents |
| Different VPCs | PrivateLink handles cross-VPC without touching the hub |
| New agent onboarding | Just add a VPC Interface Endpoint in their Terraform — hub unchanged |

### Architecture Diagram

```
┌────────────────────────────────────────────────────────────┐
│               Central Observability VPC                    │
│                                                            │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  ECS Fargate                                        │  │
│  │  ├── langfuse-web   (port 3000)                     │  │
│  │  └── langfuse-worker (background jobs)              │  │
│  └───────────────────────────────────────────────────┬─┘  │
│                      ↓                               │     │
│  ┌───────────────────┐   ┌──────────────────┐        │     │
│  │ Aurora Serverless │   │ ElastiCache Redis│        │     │
│  │ v2 (PostgreSQL)   │   │ (queue / cache)  │        │     │
│  └───────────────────┘   └──────────────────┘        │     │
│                                                       │     │
│  ┌────────────────────────────────────────────────┐  │     │
│  │  Network Load Balancer (NLB)                   │  │     │
│  │  → targets: ECS tasks on port 3000             │  │     │
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
   │  CH MAIA VPC   │  │ Future Agent   │  │ Future Agent   │
   │  Interface     │  │ VPC Interface  │  │ VPC Interface  │
   │  Endpoint      │  │ Endpoint       │  │ Endpoint       │
   │  10.x.x.x:3000 │  │  10.y.y.y:3000│  │ 10.z.z.z:3000 │
   └──────────┬─────┘  └───────┬────────┘  └────┬───────────┘
              │                │                 │
   ┌──────────▼─────┐  ┌───────▼────────┐  ┌────▼───────────┐
   │ MAIA Agent     │  │ Agent B code   │  │ Agent C code   │
   │ LANGFUSE_HOST= │  │ LANGFUSE_HOST= │  │ LANGFUSE_HOST= │
   │ langfuse.      │  │ langfuse.      │  │ langfuse.      │
   │ internal.bayer │  │ internal.bayer │  │ internal.bayer │
   └────────────────┘  └────────────────┘  └────────────────┘
```

### Key technical constraint (CRITICAL)
AWS PrivateLink **requires a Network Load Balancer (NLB)** as the endpoint service target.
An Application Load Balancer (ALB) **cannot** be a PrivateLink endpoint service.
The official Langfuse Terraform module uses ALB — this repo must replace it with NLB,
or put NLB in front of ALB as an NLB→ALB proxy (less clean but valid).
**Recommendation**: NLB directly targeting ECS tasks on port 3000 (no ALB needed).

---

## 3. Langfuse Multi-Agent Support (Built-In, Framework-Agnostic)

Langfuse natively handles everything the platform needs:

- **Organizations**: `PX CH Parchai Platform` (one org for the whole team)
- **Projects**: one per agent — `CH MAIA`, `Top Loss`, `Future Agent X`
- **Sidebar**: project switcher is a first-class UI element — clicking switches context
- **API keys**: each project has its own `LANGFUSE_PUBLIC_KEY` + `LANGFUSE_SECRET_KEY`
- **Data isolation**: Langfuse enforces project-level isolation at the DB query level
- **Evaluations, scores, datasets**: all scoped per project

### Langfuse is NOT LangChain-only — three integration paths

| Agent type | Integration method | Effort |
|---|---|---|
| LangChain / LangGraph (current MAIA agents) | `CallbackHandler` — auto-traces everything | Drop-in |
| Strands-based agents | `langfuse-strands` plugin | Drop-in |
| Any Python agent (no framework) | `@observe()` decorator on key functions | Low |
| **AWS AgentCore Runtime / Harness (any agent)** | **OTEL exporter env vars — zero code change** | Zero |

### The AgentCore OTEL path (most important for this platform)

AgentCore already emits OTEL traces — visible in existing CloudWatch logs:
```
trace_id=6ac65ed96473d3732f6d6bf97583b82c
span_id=dd14dcbc8477e439
resource.service.name=ai_a2a_euc1_dev_agentcore_maia_agent_v6.DEFAULT
OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED=true
```

Langfuse 3.x has a native OTEL ingestion endpoint (`/api/public/otel`).
**Any** AgentCore agent (regardless of internal framework) can pipe all its spans into
Langfuse by setting two environment variables — no code changes to the agent:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://langfuse.internal.bayer/api/public/otel
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic <base64(pk-lf-...:sk-lf-...)>
```

These env vars go into the AgentCore runtime's environment (via `agents_config.yml` or
Terraform `environment_variables`). Every future agent onboarded to AgentCore automatically
gets Langfuse traces without any per-agent code change.

### LangChain/LangGraph (additional richness on top of OTEL)

```python
from langfuse.callback import CallbackHandler

langfuse_handler = CallbackHandler(
    public_key=os.environ["LANGFUSE_PUBLIC_KEY"],   # from Secrets Manager
    secret_key=os.environ["LANGFUSE_SECRET_KEY"],   # from Secrets Manager
    host=os.environ["LANGFUSE_HOST"],               # https://langfuse.internal.bayer
    session_id=session_id,
    user_id=user_email,
)
# Pass to LangChain/LangGraph:
graph.invoke(input, config={"callbacks": [langfuse_handler]})
```

The callback gives richer semantic metadata (prompt templates, chain names, token counts
per step) vs. raw OTEL spans. Use BOTH together: OTEL for infra-level spans, callback for
LLM-level detail.

### What Langfuse shows (vs. CloudWatch)

| Observable | CloudWatch | Langfuse |
|---|---|---|
| Raw log lines | ✅ | ❌ |
| LLM call latency per step | ❌ | ✅ |
| Token usage per tool/chain | ❌ | ✅ |
| Cost per session / user | ❌ | ✅ |
| Prompt input / output side-by-side | ❌ | ✅ |
| Session replay (full conversation) | ❌ | ✅ |
| Evaluation scores / human feedback | ❌ | ✅ |
| Error traces with context | Partial | ✅ |

---

## 4. AWS Environment Context

| Parameter | Value |
|---|---|
| Primary region | `eu-central-1` (Frankfurt) |
| AWS account | `873461662314` (dev) |
| Org / team | Bayer `bayer-int` GitHub |
| IaC tool | Terraform ≥ 1.14.6, AWS provider ≥ 6.0 |
| Naming convention | `ai-<usecase>-<site>-<environment>` |
| Environments | `dev` (main branch), `stage`, `prod` |
| Existing VPC | Provisioned via AWS Service Catalog (not directly managed) |
| KMS | Custom KMS CMK used for encryption at rest across the platform |
| Terraform state | S3 + DynamoDB backend (separate `.conf` per state file) |

The CH MAIA infrastructure state lives in `bayer-int/ch-px-ai-maia-infra`.
This new Langfuse repo is **independent** — its own Terraform state, its own VPC.

---

## 5. New Repository Structure

Repository name: `terraform-aws-langfuse-central` (or similar, confirm with user)

```
terraform-aws-langfuse-central/
├── CLAUDE.md                        ← instructions for Cursor agent (this file's successor)
├── README.md
├── modules/
│   ├── hub/                         ← ONE-TIME central deployment
│   │   ├── main.tf                  ← ECS cluster, Aurora, Redis, NLB, PrivateLink service
│   │   ├── variables.tf
│   │   ├── outputs.tf               ← exports endpoint_service_name, langfuse_url, etc.
│   │   ├── locals.tf
│   │   ├── ecs.tf                   ← Fargate task def (langfuse-web + langfuse-worker)
│   │   ├── database.tf              ← Aurora Serverless v2 PostgreSQL
│   │   ├── redis.tf                 ← ElastiCache Redis
│   │   ├── networking.tf            ← NLB, target groups, PrivateLink endpoint service
│   │   ├── iam.tf                   ← ECS task role, execution role
│   │   ├── secrets.tf               ← Secrets Manager: Langfuse encryption key, DB password
│   │   └── dns.tf                   ← Optional: Route53 private hosted zone for hub VPC
│   │
│   └── spoke/                       ← PER-TEAM: added to each agent team's Terraform
│       ├── main.tf                  ← VPC Interface Endpoint + security group
│       ├── variables.tf             ← vpc_id, subnet_ids, endpoint_service_name
│       ├── outputs.tf               ← endpoint DNS name
│       └── dns.tf                   ← Route53 alias: langfuse.internal → endpoint DNS
│
├── environments/
│   ├── dev/
│   │   ├── main.tf                  ← calls module "hub" with dev vars
│   │   ├── terraform.tfvars         ← gitignored (VPC IDs, sizing, etc.)
│   │   ├── backend.conf             ← gitignored (S3 bucket, key, DynamoDB table)
│   │   └── outputs.tf
│   ├── stage/
│   └── prod/
│
├── .github/
│   └── workflows/
│       ├── tf_plan.yml              ← PR: terraform plan
│       └── tf_apply.yml            ← push to main: terraform apply
│
├── .tflint.hcl
├── .checkov.yaml
└── .gitignore                       ← ignores *.tfvars, backend.conf, refs/
```

---

## 6. Hub Module — Key Components

### ⚠️ Langfuse v3 requires THREE databases (not two)

| Database | Purpose | AWS service |
|---|---|---|
| PostgreSQL | Metadata, users, projects, configs | RDS / Aurora Serverless v2 |
| **ClickHouse** | **All traces, observations, scores (analytical)** | **ECS Fargate + EFS** |
| Redis | Queue + cache | ElastiCache |

ClickHouse is the high-write analytical store added in Langfuse v3. Without it, Langfuse v3 will not start.

### ECS Fargate (Langfuse containers)

Langfuse requires **three** containers:
- `langfuse-web`: Next.js frontend + API server (port 3000)
- `langfuse-worker`: background job processor (ingests into ClickHouse, runs evals)
- `clickhouse`: ClickHouse server (port 8123 HTTP, port 9000 native) — **data on EFS volume**

`langfuse-web` and `langfuse-worker` use: `langfuse/langfuse:<version>`
ClickHouse uses: `clickhouse/clickhouse-server:<version>` (pin to a stable version)

Key environment variables for Langfuse ECS tasks:
```
DATABASE_URL              = postgresql://langfuse:<pass>@<aurora-endpoint>:5432/langfuse
CLICKHOUSE_URL            = http://langfuse:<pass>@<clickhouse-service-discovery>:8123
CLICKHOUSE_MIGRATION_URL  = clickhouse://langfuse:<pass>@<clickhouse-service-discovery>:9000
REDIS_URL                 = redis://<elasticache-endpoint>:6379
NEXTAUTH_URL              = https://langfuse.internal (NLB DNS or Route53 alias)
NEXTAUTH_SECRET           = <32-char secret — Secrets Manager>
LANGFUSE_ENCRYPTION_KEY   = <32-byte hex key — Secrets Manager>
SALT                      = <random salt — Secrets Manager>
NODE_ENV                  = production
# Optional: Entra SSO (leave blank for dev, populate for prod)
AUTH_ENTRA_ID_CLIENT_ID   = ""
AUTH_ENTRA_ID_CLIENT_SECRET = ""
AUTH_ENTRA_ID_TENANT_ID   = ""
AUTH_DISABLE_SIGNUP       = "false"   # set true once SSO is configured
```

### ClickHouse on ECS + EFS

- Run as a single-node ClickHouse container on ECS Fargate
- Persistent storage via **Amazon EFS** mounted at `/var/lib/clickhouse`
- EFS access point with UID/GID matching ClickHouse container user (101:101)
- Security group: allow ports 8123 + 9000 from Langfuse ECS tasks only (not internet-facing)
- ClickHouse user: `langfuse` with password from Secrets Manager
- For high-scale prod: swap to ClickHouse Cloud by changing `CLICKHOUSE_URL` env var — no infra change needed

### Aurora Serverless v2 (PostgreSQL)
- Engine: PostgreSQL 15 compatible
- Min ACUs: 0.5 (dev), 1 (prod)
- Max ACUs: 4 (dev), 16 (prod)
- Database name: `langfuse`
- Encryption: dedicated KMS CMK

### ElastiCache Redis
- Engine: Redis 7.x
- Node type: `cache.t4g.micro` (dev), `cache.t4g.medium` (prod)
- Encryption: at-rest + in-transit

### NLB → PrivateLink
- NLB listener: TCP port 3000 (dev), TCP 443 (prod with ACM cert)
- `tls_enabled` variable controls mode — no module rewrite needed to upgrade
- Target group: ECS tasks IP-based (required for Fargate)
- `aws_vpc_endpoint_service` attached to NLB
- `allowed_principals`: same-account wildcard for dev; explicit ARNs for cross-account
- `acceptance_required = false` for same-account, `true` for cross-account

### DNS
- Route53 **new** private hosted zone: `langfuse.internal`
- Created and managed by hub module
- A-record alias: `langfuse.internal` → NLB DNS
- Associated with hub VPC and each spoke VPC on request
- Spoke module associates its VPC with this hosted zone on creation

---

## 7. Spoke Module — Per-Team Onboarding

When a new agent team joins the platform, they add this to **their existing Terraform**:

```hcl
module "langfuse_spoke" {
  source = "git::https://github.com/bayer-int/terraform-aws-langfuse-central.git//modules/spoke?ref=v1.0.0"

  vpc_id                = var.vpc_id
  private_subnet_ids    = var.private_subnet_ids
  endpoint_service_name = "com.amazonaws.vpce.eu-central-1.vpce-svc-XXXXXXXXXXXXXXXXX"
  # ^ output from hub module, communicated via README or SSM Parameter
  
  tags = {
    Environment = var.environment
    Project     = "CH MAIA"
  }
}

output "langfuse_endpoint_dns" {
  value = module.langfuse_spoke.endpoint_dns
}
```

The spoke creates:
1. `aws_vpc_endpoint` (Interface type) connecting to the PrivateLink service
2. Security group allowing outbound TCP 3000 from agent tasks
3. Optional Route53 private hosted zone alias record

---

## 8. Trust Boundary — Who Should Use This Hub vs. Fork It

### This hub is for: PX CH Parchai Platform agents only

The centralized hub deploys ONE Langfuse instance. Langfuse Projects provide *logical*
isolation (separate API keys, separate UI views per agent), but:
- A Langfuse **admin** of the instance can see ALL projects
- The underlying PostgreSQL database is shared
- There is no cryptographic isolation between projects at the DB layer

**Therefore: only agents owned by the same team (same trust domain) should use the same hub.**

For the CH MAIA team this means:
- ✅ CH MAIA agent → project in this hub
- ✅ Top Loss agent → project in this hub
- ✅ Future PX CH Parchai Platform agents → projects in this hub
- ❌ Separate Bayer team (different org, different data privacy requirements) → they fork the repo

### For external/separate teams: fork this repo, don't connect to our hub

Another Bayer team that wants Langfuse observability for their own agents should:
1. **Fork `terraform-aws-langfuse-central`** (our repo — not the official Langfuse one)
2. Deploy their own independent hub in their own AWS account
3. Connect only their own agent VPCs as spokes

**Why fork ours, not the official `langfuse/langfuse-terraform-aws`?**

| | Official Langfuse Terraform | Our repo |
|---|---|---|
| NLB + PrivateLink ready | ❌ (ALB only) | ✅ |
| Hub/Spoke pattern | ❌ | ✅ |
| Full Secrets Manager | Basic | ✅ |
| KMS encryption everywhere | Basic | ✅ |
| CI/CD workflows | ❌ | ✅ |
| Production AWS patterns | Partial | ✅ |

Our repo is the better baseline — they just swap VPC IDs, AWS account, and naming prefix.
Result: complete physical isolation — separate Aurora DB, separate ECS cluster, separate
PrivateLink endpoint. Zero data leakage between teams.

### Summary

```
terraform-aws-langfuse-central (our repo)
│
├── DEPLOYED → CH MAIA team hub (eu-central-1, account 873461662314)
│   Spoke VPCs: CH MAIA, Top Loss, future PX CH agents
│   Admin: CH MAIA team only
│
└── FORKED → Team B deploys their own hub (their account, their VPC)
    Spoke VPCs: Team B's agents only
    Admin: Team B only
    Data: completely isolated — different DB, different instance
```

## 9. Security Model

- **API Gateway → Langfuse**: not applicable — agents call Langfuse directly (SDK), not via API Gateway
- **NLB**: internal-facing only (no internet-facing NLB)
- **PrivateLink**: traffic never leaves AWS backbone — no public internet
- **VPC Endpoint security group**: restricts ingress to agent task security groups only
- **Secrets**: all sensitive values (DB password, NEXTAUTH_SECRET, encryption key) in AWS Secrets Manager, referenced by ECS task definition via `secrets:` block
- **IAM**: ECS task execution role needs `secretsmanager:GetSecretValue` on the Langfuse secrets
- **KMS**: Aurora + Secrets Manager encrypted with the platform's CMK (or a dedicated CMK for this stack)

---

## 9. CI/CD

Two GitHub Actions workflows (same pattern as `ch-px-ai-maia-infra`):
- **`tf_plan.yml`**: triggered on PR to `main`/`stage`/`prod` — runs `terraform plan`, posts diff as PR comment
- **`tf_apply.yml`**: triggered on push to `main`/`stage`/`prod` — runs `terraform apply`

Auth to AWS via OIDC (no long-lived keys). Same `ORG_REPOS_INTERNAL_READ_ONLY` PAT needed for private modules if referenced.

---

## 10. Langfuse Version & Docker Image Strategy

- Use a **pinned** Langfuse version in the ECS task definition (not `latest`)
- Check https://github.com/langfuse/langfuse/releases for latest stable
- Version variable in `variables.tf` so it's easy to bump:
  ```hcl
  variable "langfuse_version" {
    description = "Langfuse Docker image tag to deploy."
    type        = string
    default     = "3.22.0"  # update to latest stable at time of implementation
  }
  ```
- Image: `langfuse/langfuse:${var.langfuse_version}`

---

## 11. What the Official Langfuse Terraform Repo Provides (and what to change)

Official repo: `https://github.com/langfuse/langfuse-terraform-aws` (or fork/check for latest)

**Reuse as-is**:
- ECS task definition structure
- Aurora + Redis resource patterns
- IAM roles
- Secrets Manager patterns
- CloudWatch log groups

**Must change/add**:
- Replace ALB with **NLB** (ALB cannot be PrivateLink endpoint service target)
- Add `aws_vpc_endpoint_service` resource
- Add `spoke` module (not in official repo)
- Adapt for internal-only deployment (remove public internet-facing resources)
- Add Route53 private hosted zone for DNS resolution

---

## 12. Implementation Order (What to Build First)

1. **`modules/hub/networking.tf`** — VPC data sources, NLB, target groups, PrivateLink service (unblocks everything else)
2. **`modules/hub/secrets.tf`** — Secrets Manager resources (DB password, NEXTAUTH_SECRET, encryption key)
3. **`modules/hub/database.tf`** — Aurora Serverless v2 cluster + subnet group
4. **`modules/hub/redis.tf`** — ElastiCache Redis cluster
5. **`modules/hub/iam.tf`** — ECS task role + execution role
6. **`modules/hub/ecs.tf`** — ECS cluster + service + task definition (web + worker)
7. **`modules/hub/dns.tf`** — Route53 private hosted zone + A record
8. **`modules/hub/main.tf` + `variables.tf` + `outputs.tf`** — wire it all together
9. **`modules/spoke/`** — VPC Interface Endpoint + security group + DNS alias
10. **`environments/dev/`** — instantiate hub module, plug in dev VPC details
11. **CI/CD workflows** — `tf_plan.yml` + `tf_apply.yml`
12. **Documentation** — README with spoke onboarding instructions for other teams

---

## 13. Pre-Build Questions — Answers Already Decided

These were clarified before starting implementation. Do not re-ask the user.

| # | Question | Answer |
|---|---|---|
| 1 | Workspace migration | Replace EKS-based root entirely with `modules/hub` + `modules/spoke` + `environments/` |
| 2 | ClickHouse | **Option B — ECS Fargate + EFS** (single-node, data sovereignty, no new SaaS vendor) |
| 3 | Hub VPC | No existing Central Observability VPC. Hub module **accepts VPC ID + subnet IDs as variables** — VPC provisioned separately via AWS Service Catalog |
| 4 | Route53 | No existing PHZ. Hub module **creates a new private hosted zone** (`langfuse.internal`) |
| 5 | KMS | **Dedicated CMK** created by this repo — no dependency on MAIA CMK |
| 6 | Cross-account | Same account (873461662314) for now. Add `allowed_principals` variable for future cross-account |
| 7 | Langfuse version | Latest stable 3.x, pinned in `langfuse_version` variable |
| 8 | UI auth | **Email/password for dev**. Entra SSO variables present but empty — enabled for prod by populating them |
| 9 | TLS | **Plain TCP port 3000 for dev**. `tls_enabled` + ACM cert ARN variable for prod upgrade |

## 14. Open Questions for User to Answer Before Starting

These need answers before writing Terraform — ask the user at the start of the new conversation:

1. **Hub VPC**: Does a "Central Observability VPC" already exist, or does this repo also provision it? (Most likely: existing VPC from AWS Service Catalog — get the VPC ID and private subnet IDs)
2. **DNS**: Does `internal.bayer` Route53 private hosted zone exist already (shared infra), or does this repo create it?
3. **KMS**: Use the same platform CMK from `ch-px-ai-maia-infra`, or a new dedicated CMK?
4. **Cross-account?**: Are future agent VPCs in the SAME AWS account (873461662314) or different accounts? (Affects PrivateLink `allowed_principals` config)
5. **Langfuse version**: What is the latest stable version at the time of starting? (Check https://github.com/langfuse/langfuse/releases)
6. **Authentication to Langfuse UI**: SSO via Entra ID (SAML/OIDC)? Or email+password for now? (Langfuse supports Entra SSO — recommended for Bayer)
7. **Repo name**: Confirm final GitHub repo name (e.g. `bayer-int/terraform-aws-langfuse-central`)
8. **TLS**: TLS termination at NLB (requires ACM cert) or plain HTTP inside VPC? (For internal-only traffic, plain HTTP inside VPC is acceptable for dev)

---

## 14. Quick Reference — Key Resource Names (follow platform naming convention)

| Resource | Suggested name |
|---|---|
| ECS cluster | `ai-langfuse-euc1-dev` |
| ECS service (web) | `ai-langfuse-web-euc1-dev` |
| ECS service (worker) | `ai-langfuse-worker-euc1-dev` |
| Aurora cluster | `ai-langfuse-db-euc1-dev` |
| ElastiCache | `ai-langfuse-cache-euc1-dev` |
| NLB | `ai-langfuse-nlb-euc1-dev` |
| Secrets Manager | `ai/langfuse/euc1/dev/db-password`, `ai/langfuse/euc1/dev/nextauth-secret`, etc. |
| CloudWatch log group | `/ecs/ai-langfuse-euc1-dev` |

---

*Last updated: 2026-10-08 by Cursor agent session on `bayer-int/ch-px-ai-maia-infra`*
*Start the new conversation by opening this file in the new repo's workspace and saying:*
*"Read refs/langfuse-aws-project-brief.md and let's start building."*
