module "vault" {
  # tflint-ignore: terraform_module_pinned_source
  source = "git::https://github.com/craigsloggett/terraform-aws-vault-enterprise"

  vault_enterprise_license = var.vault_enterprise_license
  vault_fqdn               = var.vault_fqdn

  nlb = {
    # Deletion protection blocks `terraform destroy` of this example.
    deletion_protection = false
  }
}
