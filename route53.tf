resource "aws_route53_record" "vault_enterprise" {
  count = var.route53_zone == null ? 0 : 1

  zone_id = var.route53_zone.zone_id
  name    = var.vault_fqdn
  type    = "A"

  alias {
    name                   = aws_lb.vault_enterprise.dns_name
    zone_id                = aws_lb.vault_enterprise.zone_id
    evaluate_target_health = true
  }

  lifecycle {
    precondition {
      condition     = endswith(var.vault_fqdn, ".${var.route53_zone.name}")
      error_message = "vault_fqdn must be a subdomain of var.route53_zone.name (if provided)."
    }
  }
}
