variable "name_prefix" {
  description = "Resource naming prefix following platform conventions (e.g. ai-langfuse-euc1-dev)."
  type        = string
  default     = "ai-langfuse-euc1-dev"
}

variable "environment" {
  description = "Target deployment environment (dev, stage, prod)."
  type        = string
  default     = "dev"
}

variable "vpc_id" {
  description = "VPC ID of the Central Observability VPC (provisioned via Service Catalog)."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks, Aurora, Redis, and internal NLB."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "Aurora Serverless v2 and NLB require private_subnet_ids to contain at least two subnets across distinct Availability Zones."
  }
}

variable "allowed_principals" {
  description = "List of AWS IAM principal ARNs allowed to connect to the PrivateLink Endpoint Service."
  type        = list(string)
  default     = []
}

variable "port" {
  description = "TCP port on which Langfuse web container listens."
  type        = number
  default     = 3000
}

variable "langfuse_version" {
  description = "Langfuse Docker image tag to deploy (pinned stable version)."
  type        = string
  default     = "3.22.0"
}

variable "langfuse_image" {
  description = "Langfuse Web Docker image repository."
  type        = string
  default     = "langfuse/langfuse"
}

variable "langfuse_worker_image" {
  description = "Langfuse Worker Docker image repository."
  type        = string
  default     = "langfuse/langfuse-worker"
}

variable "kms_key_arn" {
  description = "ARN of an existing KMS CMK for encryption at rest. If null or empty, a dedicated CMK is created."
  type        = string
  default     = null
}

variable "db_min_capacity" {
  description = "Minimum Aurora Serverless v2 ACUs (0.5 minimum)."
  type        = number
  default     = 0.5
}

variable "db_max_capacity" {
  description = "Maximum Aurora Serverless v2 ACUs (4 for dev, 16 for prod)."
  type        = number
  default     = 4.0
}

variable "db_name" {
  description = "Name of the PostgreSQL database."
  type        = string
  default     = "langfuse"
}

variable "db_username" {
  description = "Master username for the PostgreSQL database."
  type        = string
  default     = "langfuse"
}

variable "redis_node_type" {
  description = "ElastiCache node type (cache.t4g.micro for dev, cache.r7g.large for prod)."
  type        = string
  default     = "cache.t4g.micro"
}

variable "redis_num_nodes" {
  description = "Number of cache nodes in the ElastiCache replication group (1 for dev, 2+ for multi-AZ prod)."
  type        = number
  default     = 1
}

variable "ecs_cpu" {
  description = "Total CPU units allocated to the ECS Fargate task (1024 = 1 vCPU, 2048 = 2 vCPU)."
  type        = number
  default     = 2048
}

variable "ecs_memory" {
  description = "Total memory (MiB) allocated to the ECS Fargate task."
  type        = number
  default     = 4096
}

variable "ecs_web_cpu" {
  description = "CPU units allocated to the langfuse-web container."
  type        = number
  default     = 1024
}

variable "ecs_web_memory" {
  description = "Memory (MiB) allocated to the langfuse-web container."
  type        = number
  default     = 2048
}

variable "ecs_worker_cpu" {
  description = "CPU units allocated to the langfuse-worker container."
  type        = number
  default     = 1024
}

variable "ecs_worker_memory" {
  description = "Memory (MiB) allocated to the langfuse-worker container."
  type        = number
  default     = 2048
}

variable "ecs_desired_count" {
  description = "Desired number of running ECS task instances."
  type        = number
  default     = 1
}

variable "create_dns_zone" {
  description = "Whether to create a new Route53 Private Hosted Zone for the hub VPC."
  type        = bool
  default     = false
}

variable "dns_zone_name" {
  description = "Name of the Route53 Private Hosted Zone (e.g. internal.bayer)."
  type        = string
  default     = "internal.bayer"
}

variable "dns_zone_id" {
  description = "ID of an existing Route53 Private Hosted Zone (if create_dns_zone is false)."
  type        = string
  default     = null
}

variable "dns_record_name" {
  description = "DNS record name for Langfuse within the private zone."
  type        = string
  default     = "langfuse"
}

variable "clickhouse_url" {
  description = "External ClickHouse HTTP URL (e.g. http://clickhouse.internal:8123 or ClickHouse Cloud endpoint)."
  type        = string
  default     = null
}

variable "clickhouse_migration_url" {
  description = "External ClickHouse TCP migration URL (e.g. clickhouse://clickhouse.internal:9000)."
  type        = string
  default     = null
}

variable "clickhouse_user" {
  description = "ClickHouse user name."
  type        = string
  default     = "default"
}

variable "clickhouse_password" {
  description = "ClickHouse password (sensitive). If null and external ClickHouse is configured, a secret will still be provisioned."
  type        = string
  default     = null
  sensitive   = true
}

variable "clickhouse_db" {
  description = "ClickHouse database name."
  type        = string
  default     = "default"
}

variable "enable_embedded_clickhouse" {
  description = "Whether to deploy a single-node ClickHouse container in the ECS task for standalone environments."
  type        = bool
  default     = false
}

variable "entra_client_id" {
  description = "Microsoft Entra ID Client ID for SSO (optional)."
  type        = string
  default     = null
}

variable "entra_client_secret" {
  description = "Microsoft Entra ID Client Secret for SSO (optional, sensitive)."
  type        = string
  default     = null
  sensitive   = true
}

variable "entra_tenant_id" {
  description = "Microsoft Entra ID Tenant ID for SSO (optional)."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Retention period in days for CloudWatch log groups."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Common tags to apply to all resources."
  type        = map(string)
  default     = {}
}
