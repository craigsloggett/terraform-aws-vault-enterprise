# tflint-ignore: terraform_required_version
# tflint-ignore: terraform_module_version
module "vault" {
  source = "../../"

  project_name      = "vault-ha"
  route53_zone_name = var.route53_zone_name
  vault_license     = var.vault_license
  ec2_key_pair_name = var.ec2_key_pair_name
}
