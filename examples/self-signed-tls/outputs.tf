output "vault_url" {
  description = "URL of the Vault cluster."
  value       = module.vault.vault_url
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host."
  value       = module.vault.bastion_public_ip
}

output "nlb_dns_name" {
  description = "AWS-assigned DNS name of the Vault NLB."
  value       = module.vault.nlb_dns_name
}

output "nlb_zone_id" {
  description = "Hosted zone ID of the Vault NLB."
  value       = module.vault.nlb_zone_id
}
