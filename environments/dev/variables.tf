variable "name_prefix" {
  description = "Resource naming prefix (defaults to ai-langfuse-euc1-dev)."
  type        = string
  default     = null
}

variable "owner" {
  description = "Owner team tag."
  type        = string
  default     = "PX-CH-Team"
}

variable "platform" {
  description = "Platform name tag."
  type        = string
  default     = "PX-CH-Parchai"
}

variable "aws_region" {
  description = "AWS deployment region."
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"
}

variable "vpc_id" {
  description = "VPC ID of the Central Observability VPC (provisioned via AWS Service Catalog)."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for deploying ECS tasks, Aurora, Redis, and internal NLB."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "Aurora Serverless v2 and NLB require private_subnet_ids to contain at least two subnets across distinct Availability Zones."
  }
}

variable "create_dns_zone" {
  description = "Whether to create a Route53 private hosted zone."
  type        = bool
  default     = false
}

variable "dns_zone_id" {
  description = "Existing Route53 private hosted zone ID (optional)."
  type        = string
  default     = null
}

variable "allowed_principals" {
  description = "ARNs allowed to connect to the PrivateLink Endpoint Service. The current AWS account is automatically included dynamically; add any cross-account ARNs here."
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
  default     = 0.5
}

variable "db_max_capacity" {
  description = "Maximum Aurora Serverless v2 ACUs."
  type        = number
  default     = 4.0
}

variable "redis_node_type" {
  description = "ElastiCache node type."
  type        = string
  default     = "cache.t4g.micro"
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
  default     = true
}

variable "tags" {
  description = "Custom tags for all resources in this environment."
  type        = map(string)
  default     = {}
}
