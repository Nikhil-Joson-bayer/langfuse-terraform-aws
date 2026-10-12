# -----------------------------------------------------------------------------
# AWS PrivateLink & Networking Outputs (Crucial for Spoke Modules)
# -----------------------------------------------------------------------------
output "endpoint_service_name" {
  description = "The Service Name of the PrivateLink VPC Endpoint Service (pass this to spoke modules)."
  value       = aws_vpc_endpoint_service.langfuse.service_name
}

output "endpoint_service_id" {
  description = "The ID of the PrivateLink VPC Endpoint Service."
  value       = aws_vpc_endpoint_service.langfuse.id
}

output "nlb_arn" {
  description = "The ARN of the internal Network Load Balancer."
  value       = aws_lb.nlb.arn
}

output "nlb_dns_name" {
  description = "The DNS name of the internal Network Load Balancer."
  value       = aws_lb.nlb.dns_name
}

output "nlb_zone_id" {
  description = "The canonical hosted zone ID of the internal Network Load Balancer."
  value       = aws_lb.nlb.zone_id
}

output "langfuse_url" {
  description = "The internal URL for accessing Langfuse web UI and API."
  value       = local.effective_web_url
}

output "dns_name" {
  description = "The full DNS hostname configured for Langfuse."
  value       = local.full_dns_name
}

output "dns_zone_id" {
  description = "The Route53 Hosted Zone ID used for Langfuse."
  value       = local.resolved_zone_id
}

output "ecs_tasks_security_group_id" {
  description = "The security group ID assigned to the Langfuse ECS tasks."
  value       = aws_security_group.ecs_tasks.id
}

# -----------------------------------------------------------------------------
# ECS Outputs
# -----------------------------------------------------------------------------
output "ecs_cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster."
  value       = aws_ecs_cluster.main.arn
}

output "ecs_service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.langfuse.name
}

output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role."
  value       = aws_iam_role.ecs_execution_role.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role."
  value       = aws_iam_role.ecs_task_role.arn
}

# -----------------------------------------------------------------------------
# Database, Cache & Storage Outputs
# -----------------------------------------------------------------------------
output "aurora_cluster_endpoint" {
  description = "Writer endpoint for the Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.postgresql.endpoint
}

output "aurora_cluster_reader_endpoint" {
  description = "Reader endpoint for the Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.postgresql.reader_endpoint
}

output "aurora_database_name" {
  description = "Name of the default PostgreSQL database."
  value       = var.db_name
}

output "redis_primary_endpoint" {
  description = "Primary endpoint address for the ElastiCache Redis cluster."
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_port" {
  description = "Port number for the ElastiCache Redis cluster."
  value       = local.redis_port
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket used for Langfuse event batch uploads."
  value       = aws_s3_bucket.events.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket used for Langfuse event batch uploads."
  value       = aws_s3_bucket.events.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS Key used for encrypting all hub resources."
  value       = local.kms_key_arn
}

# -----------------------------------------------------------------------------
# Secrets Manager Outputs
# -----------------------------------------------------------------------------
output "db_credentials_secret_arn" {
  description = "Secrets Manager ARN containing PostgreSQL credentials."
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "app_secrets_secret_arn" {
  description = "Secrets Manager ARN containing Langfuse application secrets."
  value       = aws_secretsmanager_secret.app_secrets.arn
}

output "redis_credentials_secret_arn" {
  description = "Secrets Manager ARN containing Redis credentials."
  value       = aws_secretsmanager_secret.redis_credentials.arn
}

output "clickhouse_credentials_secret_arn" {
  description = "Secrets Manager ARN containing ClickHouse credentials (if configured)."
  value       = local.clickhouse_enabled ? aws_secretsmanager_secret.clickhouse_credentials[0].arn : null
}
