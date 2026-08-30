data "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    sid     = "GitHubEnvironmentDeployments"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repository}:environment:production",
        "repo:${var.github_repository}:environment:staging",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = var.github_actions_role_name
  description          = "Push voting application images to ECR and deploy them to EKS"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_trust.json
  max_session_duration = 3600
  tags                 = var.tags
}

data "aws_iam_policy_document" "github_actions_deployment" {
  statement {
    sid       = "ECRLogin"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PushApplicationImages"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [
      "arn:aws:ecr:*:${data.aws_caller_identity.current.account_id}:repository/${var.ecr_repository_prefix}/*",
    ]
  }

  statement {
    sid       = "DiscoverDeploymentCluster"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:aws:eks:*:${data.aws_caller_identity.current.account_id}:cluster/${var.eks_cluster_name}"]
  }
}

resource "aws_iam_policy" "github_actions_deployment" {
  name        = "${var.github_actions_role_name}-deployment"
  description = "Push immutable application images to ECR and connect to the deployment EKS cluster"
  policy      = data.aws_iam_policy_document.github_actions_deployment.json
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "github_actions_deployment" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_deployment.arn
}
