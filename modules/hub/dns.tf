# -----------------------------------------------------------------------------
# Route53 Private Hosted Zone (Optional: created if create_dns_zone = true)
# -----------------------------------------------------------------------------
resource "aws_route53_zone" "private" {
  count = var.create_dns_zone ? 1 : 0
  name  = var.dns_zone_name

  vpc {
    vpc_id = var.vpc_id
  }

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-private-zone"
    }
  )
}

locals {
  resolved_zone_id  = var.create_dns_zone ? aws_route53_zone.private[0].zone_id : var.dns_zone_id
  full_dns_name     = "${var.dns_record_name}.${var.dns_zone_name}"
  effective_web_url = local.resolved_zone_id != null ? "http://${local.full_dns_name}:${var.port}" : "http://${aws_lb.nlb.dns_name}:${var.port}"
}

# -----------------------------------------------------------------------------
# Route53 Alias Record pointing to the internal NLB
# -----------------------------------------------------------------------------
resource "aws_route53_record" "langfuse" {
  count   = local.resolved_zone_id != null ? 1 : 0
  zone_id = local.resolved_zone_id
  name    = var.dns_record_name
  type    = "A"

  alias {
    name                   = aws_lb.nlb.dns_name
    zone_id                = aws_lb.nlb.zone_id
    evaluate_target_health = true
  }
}
