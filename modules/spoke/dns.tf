# -----------------------------------------------------------------------------
# Route53 CNAME record pointing friendly hostname to VPC Endpoint DNS
# -----------------------------------------------------------------------------
resource "aws_route53_record" "langfuse" {
  count   = var.dns_zone_id != null ? 1 : 0
  zone_id = var.dns_zone_id
  name    = var.dns_record_name
  type    = "CNAME"
  ttl     = 300
  records = [lookup(aws_vpc_endpoint.langfuse.dns_entry[0], "dns_name")]
}
