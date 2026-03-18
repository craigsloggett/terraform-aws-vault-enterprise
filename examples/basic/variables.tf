variable "vault_license" {
  type        = string
  description = "Vault Enterprise license string."
  sensitive   = true
}

variable "route53_zone_name" {
  type        = string
  description = "Name of the existing Route 53 hosted zone."
}

variable "ec2_key_pair_name" {
  type        = string
  description = "Name of an existing EC2 key pair for SSH access."
}
