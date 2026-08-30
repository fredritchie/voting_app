data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "hcp_terraform" {
  url = "https://app.terraform.io"

  client_id_list = [
    "aws.workload.identity",
  ]

  tags = var.tags
}

data "aws_iam_policy_document" "hcp_terraform_trust" {
  statement {
    sid     = "HCPWorkspacePlanAndApply"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.hcp_terraform.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "app.terraform.io:aud"
      values   = ["aws.workload.identity"]
    }

    condition {
      test     = "StringLike"
      variable = "app.terraform.io:sub"
      values = [
        "organization:${var.hcp_terraform_organization}:project:${var.hcp_terraform_project}:workspace:${var.hcp_terraform_workspace}:run_phase:*",
      ]
    }
  }
}

resource "aws_iam_role" "hcp_terraform" {
  name                 = var.role_name
  description          = "Provision voting application AWS infrastructure from HCP Terraform"
  assume_role_policy   = data.aws_iam_policy_document.hcp_terraform_trust.json
  max_session_duration = 3600
  tags                 = var.tags
}

data "aws_iam_policy_document" "infrastructure" {
  statement {
    sid    = "ProvisionInfrastructureServices"
    effect = "Allow"
    actions = [
      "ec2:*",
      "ebs:*",
      "ecr:*",
      "eks:*",
      "cloudwatch:DeleteDashboards",
      "cloudwatch:GetDashboard",
      "cloudwatch:ListDashboards",
      "cloudwatch:PutDashboard",
      "logs:*",
      "rds:*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageApplicationIAMRoles"
    effect = "Allow"
    actions = [
      "iam:AttachRolePolicy",
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:DetachRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:PutRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:GetRole",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.application_role_name_prefix}-*",
    ]
  }

  statement {
    sid     = "PassApplicationRoles"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.application_role_name_prefix}-*",
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values = [
        "ec2.amazonaws.com",
        "eks.amazonaws.com",
        "pods.eks.amazonaws.com",
      ]
    }
  }

  statement {
    sid    = "ReadAWSManagedPolicies"
    effect = "Allow"
    actions = [
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
    ]
    resources = ["arn:aws:iam::aws:policy/*"]
  }

  statement {
    sid       = "CreateRequiredServiceLinkedRoles"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "autoscaling.amazonaws.com",
        "eks-nodegroup.amazonaws.com",
        "eks.amazonaws.com",
        "rds.amazonaws.com",
      ]
    }
  }

  statement {
    sid    = "ReadRequiredServiceLinkedRoles"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"]
  }

  statement {
    sid    = "CreateRDSManagedMasterSecret"
    effect = "Allow"
    actions = [
      "kms:DescribeKey",
      "secretsmanager:CreateSecret",
      "secretsmanager:TagResource",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "infrastructure" {
  name        = "${var.role_name}-infrastructure"
  description = "Provision the voting application's VPC, EKS, ECR, RDS, logging, and supporting IAM resources"
  policy      = data.aws_iam_policy_document.infrastructure.json
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "infrastructure" {
  role       = aws_iam_role.hcp_terraform.name
  policy_arn = aws_iam_policy.infrastructure.arn
}
