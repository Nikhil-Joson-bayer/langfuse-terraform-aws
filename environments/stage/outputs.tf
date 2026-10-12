output "endpoint_service_name" {
  description = "The PrivateLink VPC Endpoint Service name to distribute to spoke agent teams."
  value       = module.hub.endpoint_service_name
}

output "endpoint_service_id" {
  description = "The ID of the VPC Endpoint Service."
  value       = module.hub.endpoint_service_id
}

output "nlb_dns_name" {
  description = "DNS name of the internal Network Load Balancer."
  value       = module.hub.nlb_dns_name
}

output "langfuse_url" {
  description = "Internal URL to access Langfuse UI."
  value       = module.hub.langfuse_url
}

output "aurora_cluster_endpoint" {
  description = "Writer endpoint for Aurora PostgreSQL."
  value       = module.hub.aurora_cluster_endpoint
}

output "redis_primary_endpoint" {
  description = "Primary endpoint for ElastiCache Redis."
  value       = module.hub.redis_primary_endpoint
}

output "s3_bucket_name" {
  description = "S3 bucket name for Langfuse event batch uploads."
  value       = module.hub.s3_bucket_name
}
