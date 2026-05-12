locals {
  # VPC Configuration
  vpc = var.vpc.existing != null ? {
    id                 = var.vpc.existing.vpc_id
    cidr               = data.aws_vpc.existing[0].cidr_block
    private_subnet_ids = var.vpc.existing.private_subnet_ids
    public_subnet_ids  = var.vpc.existing.public_subnet_ids
    } : {
    id                 = module.vpc[0].vpc_id
    cidr               = var.vpc.cidr
    private_subnet_ids = module.vpc[0].private_subnets
    public_subnet_ids  = module.vpc[0].public_subnets
  }
}
