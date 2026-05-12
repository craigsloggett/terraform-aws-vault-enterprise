variable "vault_enterprise_license" {
  type        = string
  description = "Vault Enterprise license string."
  sensitive   = true
}

variable "vault_fqdn" {
  type        = string
  description = "Fully qualified domain name in presentation form for the Vault Enterprise cluster."
}
