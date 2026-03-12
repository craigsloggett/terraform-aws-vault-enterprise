# tflint-ignore: terraform_required_version
module "vault" {
  source = "craigsloggett/vault-enterprise-ha/aws"
  # version = "x.x.x"
}
