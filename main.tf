data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "existing" {
  count = var.existing_vpc != null ? 1 : 0
  id    = var.existing_vpc.vpc_id
}
