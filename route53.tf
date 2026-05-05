resource "aws_route53_record" "vault_enterprise" {
  zone_id = var.route53_zone.zone_id
  name    = local.vault_fqdn
  type    = "A"

  alias {
    name                   = aws_lb.vault_enterprise.dns_name
    zone_id                = aws_lb.vault_enterprise.zone_id
    evaluate_target_health = true
  }
}
