variable "aws_region" {
  description = "AWS deployment region."
  type        = string
  default     = "eu-central-1"
}

variable "vpc_id" {
  description = "VPC ID of the Central Observability VPC (provisioned via AWS Service Catalog)."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for deploying ECS tasks, Aurora, Redis, and internal NLB."
  type        = list(string)
}

variable "allowed_principals" {
  description = "ARNs allowed to connect to the PrivateLink Endpoint Service."
  type        = list(string)
  default     = []
}

variable "langfuse_version" {
  description = "Pinned Langfuse Docker image version."
  type        = string
  default     = "3.22.0"
}

variable "kms_key_arn" {
  description = "Optional existing KMS CMK ARN from platform infra. If null, dedicated CMK is created."
  type        = string
  default     = null
}

variable "db_min_capacity" {
  description = "Minimum Aurora Serverless v2 ACUs."
  type        = number
  default     = 1.0
}

variable "db_max_capacity" {
  description = "Maximum Aurora Serverless v2 ACUs."
  type        = number
  default     = 16.0
}

variable "redis_node_type" {
  description = "ElastiCache node type."
  type        = string
  default     = "cache.r7g.large"
}

variable "clickhouse_url" {
  description = "External ClickHouse HTTP URL (optional)."
  type        = string
  default     = null
}

variable "clickhouse_migration_url" {
  description = "External ClickHouse TCP migration URL (optional)."
  type        = string
  default     = null
}

variable "clickhouse_user" {
  description = "ClickHouse user name."
  type        = string
  default     = "default"
}

variable "clickhouse_password" {
  description = "ClickHouse password (sensitive)."
  type        = string
  default     = null
  sensitive   = true
}

variable "enable_embedded_clickhouse" {
  description = "Whether to deploy an embedded ClickHouse container in ECS Fargate."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Custom tags for all resources in this environment."
  type        = map(string)
  default     = {}
}
