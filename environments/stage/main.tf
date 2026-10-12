provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      "Owner"       = "PX-CH-Team"
      "Platform"    = "PX-CH-Parchai"
      "Environment" = "stage"
      "ManagedBy"   = "Terraform"
    }
  }
}

module "hub" {
  source = "../../modules/hub"

  name_prefix                = "ai-langfuse-euc1-stage"
  environment                = "stage"
  vpc_id                     = var.vpc_id
  private_subnet_ids         = var.private_subnet_ids
  allowed_principals         = var.allowed_principals
  langfuse_version           = var.langfuse_version
  kms_key_arn                = var.kms_key_arn
  db_min_capacity            = var.db_min_capacity
  db_max_capacity            = var.db_max_capacity
  redis_node_type            = var.redis_node_type
  clickhouse_url             = var.clickhouse_url
  clickhouse_migration_url   = var.clickhouse_migration_url
  clickhouse_user            = var.clickhouse_user
  clickhouse_password        = var.clickhouse_password
  enable_embedded_clickhouse = var.enable_embedded_clickhouse
  tags                       = var.tags
}
