data "aws_iam_policy_document" "database_client_assume_role" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
    ]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "database_client" {
  name               = "${local.name}-database-client"
  description        = "EKS Pod Identity role used by the voting application to read its RDS-managed secret"
  assume_role_policy = data.aws_iam_policy_document.database_client_assume_role.json
}

data "aws_iam_policy_document" "database_client" {
  statement {
    sid     = "DiscoverDatabaseSecret"
    effect  = "Allow"
    actions = ["rds:DescribeDBInstances"]
    resources = [
      "*",
    ]
  }

  statement {
    sid    = "ReadDatabaseSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      aws_db_instance.postgres.master_user_secret[0].secret_arn,
    ]
  }
}

resource "aws_iam_role_policy" "database_client" {
  name   = "read-rds-master-secret"
  role   = aws_iam_role.database_client.id
  policy = data.aws_iam_policy_document.database_client.json
}

resource "aws_eks_pod_identity_association" "database_client" {
  for_each = toset(["staging", "production"])

  cluster_name    = aws_eks_cluster.tf_eks_cluster.name
  namespace       = each.value
  service_account = "voting-app-database"
  role_arn        = aws_iam_role.database_client.arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy.database_client,
  ]
}
