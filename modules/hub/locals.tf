locals {
  name_prefix = var.name_prefix

  # Resolve KMS Key ARN: use provided or fallback to the module-managed key
  kms_key_arn = var.kms_key_arn != null && var.kms_key_arn != "" ? var.kms_key_arn : aws_kms_key.langfuse[0].arn

  # Common platform tags
  common_tags = merge(
    {
      "Platform"    = "PX-CH-Parchai"
      "Service"     = "Langfuse-Central"
      "Environment" = var.environment
      "ManagedBy"   = "Terraform"
    },
    var.tags
  )

  # Standard ports
  web_port               = var.port
  db_port                = 5432
  redis_port             = 6379
  clickhouse_http_port   = 8123
  clickhouse_native_port = 9000

  # ClickHouse resolution: embedded vs external
  clickhouse_enabled = var.clickhouse_url != null || var.enable_embedded_clickhouse

  clickhouse_http_url = var.enable_embedded_clickhouse ? "http://127.0.0.1:${local.clickhouse_http_port}" : (
    var.clickhouse_url != null ? var.clickhouse_url : ""
  )

  clickhouse_migration_url = var.enable_embedded_clickhouse ? "clickhouse://127.0.0.1:${local.clickhouse_native_port}" : (
    var.clickhouse_migration_url != null ? var.clickhouse_migration_url : ""
  )
}
