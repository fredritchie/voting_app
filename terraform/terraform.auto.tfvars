aws_region              = "ap-south-1"
eks_public_access_cidrs = ["0.0.0.0/0"]
availability_zone_count = 2
deletion_protection     = false
eks_application_admin_principal_arns = [
  "arn:aws:iam::008971653023:user/root",
]