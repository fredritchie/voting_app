variable "aws_region" {
  description = "AWS region in which all infrastructure is created."
  type        = string
}

variable "project" {
  description = "Short, DNS-safe project name used in resource names and tags."
  type        = string
  default     = "voting-app"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.project))
    error_message = "project must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment, such as production, staging, or development."
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "RFC 1918 CIDR range for the VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "availability_zone_count" {
  description = "Number of AZs used for EKS and RDS. Three provides tolerance for one AZ failure."
  type        = number
  default     = 3

  validation {
    condition     = var.availability_zone_count >= 2 && var.availability_zone_count <= 3
    error_message = "availability_zone_count must be either 2 or 3."
  }
}

variable "eks_public_access_cidrs" {
  description = "Trusted CIDR blocks permitted to reach the public EKS Kubernetes API endpoint. Do not use 0.0.0.0/0."
  type        = list(string)
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed EKS node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Initial number of EKS worker nodes."
  type        = number
  default     = 3
}

variable "node_min_size" {
  description = "Minimum number of EKS worker nodes."
  type        = number
  default     = 3
}

variable "node_max_size" {
  description = "Maximum number of EKS worker nodes."
  type        = number
  default     = 6
}

variable "db_instance_class" {
  description = "RDS instance class. Choose a size appropriate for the expected workload."
  type        = string
  default     = "db.t4g.medium"
}

variable "db_allocated_storage_gib" {
  description = "Initial encrypted gp3 storage allocated to PostgreSQL, in GiB."
  type        = number
  default     = 20
}

variable "db_max_allocated_storage_gib" {
  description = "Maximum storage autoscaling limit for PostgreSQL, in GiB."
  type        = number
  default     = 100
}

variable "db_backup_retention_days" {
  description = "Number of days to retain automated RDS backups."
  type        = number
  default     = 14
}

variable "deletion_protection" {
  description = "Prevents accidental RDS deletion. Keep true for production."
  type        = bool
  default     = true
}

variable "github_actions_role_arn" {
  description = "Optional IAM role ARN used by GitHub Actions to deploy workloads to this EKS cluster."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.github_actions_role_arn == null || can(regex("^arn:aws:iam::[0-9]{12}:role/.+", var.github_actions_role_arn))
    error_message = "github_actions_role_arn must be null or a valid AWS IAM role ARN."
  }
}
