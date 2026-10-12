# =============================================================================
# Langfuse Central Observability Hub Module
# =============================================================================
# This module deploys the centralized Langfuse observability platform on AWS:
# - ECS Fargate running langfuse-web (UI & API) and langfuse-worker (async jobs)
# - Aurora Serverless v2 PostgreSQL for transactional application data
# - ElastiCache Redis 7.x for BullMQ queues and caching
# - Internal Network Load Balancer (NLB) on TCP port 3000
# - AWS PrivateLink VPC Endpoint Service for multi-VPC agent ingestion
# - KMS-encrypted AWS Secrets Manager secrets for credentials and encryption keys
# - KMS-encrypted S3 bucket for event batch uploads and media exports
# - Route53 Private Hosted Zone and alias records
# =============================================================================
