output "cluster_name" {
  description = "EKS cluster name for aws eks update-kubeconfig."
  value       = aws_eks_cluster.tf_eks_cluster.name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint. Access is limited by eks_public_access_cidrs."
  value       = aws_eks_cluster.tf_eks_cluster.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 cluster CA data for Kubernetes clients."
  value       = aws_eks_cluster.tf_eks_cluster.certificate_authority[0].data
  sensitive   = true
}

output "rds_endpoint" {
  description = "Private PostgreSQL endpoint, without a port."
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "PostgreSQL listener port."
  value       = aws_db_instance.postgres.port
}

output "rds_instance_identifier" {
  description = "RDS instance identifier used by the workloads to discover the managed secret."
  value       = aws_db_instance.postgres.identifier
}

output "rds_master_secret_arn" {
  description = "Secrets Manager ARN holding the RDS-managed master credentials."
  value       = aws_db_instance.postgres.master_user_secret[0].secret_arn
  sensitive   = true
}

output "ecr_repository_urls" {
  description = "ECR repository URLs for vote, result, and worker images."
  value       = { for name, repository in aws_ecr_repository.application : name => repository.repository_url }
}

output "cloudwatch_dashboard_urls" {
  description = "CloudWatch infrastructure and application dashboard URLs."
  value = {
    infrastructure = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.infrastructure.dashboard_name}"
    application    = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.application.dashboard_name}"
  }
}

output "container_insights_log_groups" {
  description = "Central CloudWatch log groups populated by the EKS observability add-on."
  value       = { for stream, group in aws_cloudwatch_log_group.container_insights : stream => group.name }
}
