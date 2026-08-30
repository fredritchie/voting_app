data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "${var.project}-${var.environment}"
  azs  = slice(data.aws_availability_zones.available.names, 0, var.availability_zone_count)

  az_numbers = {
    for index, az in local.azs : az => index
  }

  common_tags = {
    Application = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
