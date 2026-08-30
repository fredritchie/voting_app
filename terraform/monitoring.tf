data "aws_iam_policy_document" "cloudwatch_agent_assume_role" {
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

resource "aws_iam_role" "cloudwatch_agent" {
  name               = "${local.name}-cloudwatch-agent"
  description        = "EKS Pod Identity role for CloudWatch Container Insights"
  assume_role_policy = data.aws_iam_policy_document.cloudwatch_agent_assume_role.json
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.cloudwatch_agent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_xray" {
  role       = aws_iam_role.cloudwatch_agent.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
}

resource "aws_cloudwatch_log_group" "container_insights" {
  for_each = toset(["application", "dataplane", "host", "performance"])

  name              = "/aws/containerinsights/${local.name}/${each.value}"
  retention_in_days = var.monitoring_log_retention_days
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.tf_eks_cluster.name
  addon_name   = "eks-pod-identity-agent"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.tf_node_grp_1]
}

resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name = aws_eks_cluster.tf_eks_cluster.name
  addon_name   = "amazon-cloudwatch-observability"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  pod_identity_association {
    role_arn        = aws_iam_role.cloudwatch_agent.arn
    service_account = "cloudwatch-agent"
  }

  depends_on = [
    aws_cloudwatch_log_group.container_insights,
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.cloudwatch_agent,
    aws_iam_role_policy_attachment.cloudwatch_agent_xray,
  ]
}

resource "aws_cloudwatch_log_metric_filter" "votes_submitted" {
  name           = "${local.name}-votes-submitted"
  log_group_name = aws_cloudwatch_log_group.container_insights["application"].name
  pattern        = "\"Received vote for\""

  metric_transformation {
    name          = "VotesSubmitted"
    namespace     = "${var.project}/Application"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "application_errors" {
  name           = "${local.name}-application-errors"
  log_group_name = aws_cloudwatch_log_group.container_insights["application"].name
  pattern        = "?ERROR ?Error ?Exception ?failed ?Giving"

  metric_transformation {
    name          = "ApplicationErrors"
    namespace     = "${var.project}/Application"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_dashboard" "infrastructure" {
  dashboard_name = "${local.name}-infrastructure"

  dashboard_body = jsonencode({
    start          = "-PT6H"
    periodOverride = "inherit"
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# ${local.name} infrastructure\nEKS node health and utilization, RDS health, NAT traffic, and control-plane errors."
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "EKS nodes"
          region = var.aws_region
          period = 300
          stat   = "Average"
          metrics = [
            ["ContainerInsights", "cluster_node_count", "ClusterName", local.name, { label = "Node count" }],
            [".", "cluster_failed_node_count", ".", ".", { label = "Failed nodes" }],
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Node CPU utilization"
          region = var.aws_region
          period = 300
          metrics = [
            [{ expression = "SEARCH('{ContainerInsights,ClusterName,NodeName,InstanceId} MetricName=\"node_cpu_utilization\" ClusterName=\"${local.name}\"', 'Average', 300)", id = "nodecpu", label = "" }],
          ]
          view    = "timeSeries"
          stacked = false
          yAxis = {
            left = { min = 0, max = 100 }
          }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Node memory utilization"
          region = var.aws_region
          period = 300
          metrics = [
            [{ expression = "SEARCH('{ContainerInsights,ClusterName,NodeName,InstanceId} MetricName=\"node_memory_utilization\" ClusterName=\"${local.name}\"', 'Average', 300)", id = "nodememory", label = "" }],
          ]
          view    = "timeSeries"
          stacked = false
          yAxis = {
            left = { min = 0, max = 100 }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "RDS CPU and connections"
          region = var.aws_region
          period = 300
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.postgres.identifier, { label = "CPU %" }],
            [".", "DatabaseConnections", ".", ".", { label = "Connections", yAxis = "right" }],
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "NAT traffic to destinations"
          region = var.aws_region
          period = 300
          stat   = "Sum"
          metrics = [
            for az, gateway in aws_nat_gateway.this :
            ["AWS/NATGateway", "BytesOutToDestination", "NatGatewayId", gateway.id, { label = az }]
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 14
        width  = 24
        height = 7
        properties = {
          title  = "Recent EKS control-plane errors"
          region = var.aws_region
          view   = "table"
          query  = "SOURCE '${aws_cloudwatch_log_group.eks.name}' | fields @timestamp, @logStream, @message\n| filter @message like /(?i)(error|fail|unauthorized|denied)/\n| sort @timestamp desc\n| limit 50"
        }
      },
    ]
  })
}

resource "aws_cloudwatch_dashboard" "application" {
  dashboard_name = "${local.name}-application"

  dashboard_body = jsonencode({
    start          = "-PT6H"
    periodOverride = "inherit"
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# ${local.name} application\nStaging and production pod health, workload utilization, restarts, vote activity, and centralized application logs."
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Running application pods"
          region = var.aws_region
          period = 300
          metrics = [
            [{ expression = "SEARCH('{ContainerInsights,ClusterName,Namespace,Service} MetricName=\"service_number_of_running_pods\" ClusterName=\"${local.name}\" Namespace=\"staging\"', 'Average', 300)", id = "stagingpods", label = "" }],
            [{ expression = "SEARCH('{ContainerInsights,ClusterName,Namespace,Service} MetricName=\"service_number_of_running_pods\" ClusterName=\"${local.name}\" Namespace=\"production\"', 'Average', 300)", id = "productionpods", label = "" }],
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Application pod CPU"
          region = var.aws_region
          period = 300
          metrics = [
            [{ expression = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_cpu_utilization\" ClusterName=\"${local.name}\" Namespace=\"staging\"', 'Average', 300)", id = "stagingcpu", label = "" }],
            [{ expression = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_cpu_utilization\" ClusterName=\"${local.name}\" Namespace=\"production\"', 'Average', 300)", id = "productioncpu", label = "" }],
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Application pod memory"
          region = var.aws_region
          period = 300
          metrics = [
            [{ expression = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_memory_utilization\" ClusterName=\"${local.name}\" Namespace=\"staging\"', 'Average', 300)", id = "stagingmemory", label = "" }],
            [{ expression = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_memory_utilization\" ClusterName=\"${local.name}\" Namespace=\"production\"', 'Average', 300)", id = "productionmemory", label = "" }],
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "Container restarts"
          region = var.aws_region
          period = 300
          stat   = "Maximum"
          metrics = [
            [{ expression = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_number_of_container_restarts\" ClusterName=\"${local.name}\" Namespace=\"staging\"', 'Maximum', 300)", id = "stagingrestarts", label = "" }],
            [{ expression = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_number_of_container_restarts\" ClusterName=\"${local.name}\" Namespace=\"production\"', 'Maximum', 300)", id = "productionrestarts", label = "" }],
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "Application events from logs"
          region = var.aws_region
          period = 300
          stat   = "Sum"
          metrics = [
            ["${var.project}/Application", "VotesSubmitted", { label = "Votes submitted" }],
            [".", "ApplicationErrors", { label = "Errors" }],
          ]
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 14
        width  = 12
        height = 7
        properties = {
          title  = "Application log volume"
          region = var.aws_region
          view   = "table"
          query  = "SOURCE '${aws_cloudwatch_log_group.container_insights["application"].name}' | filter kubernetes.namespace_name in [\"staging\", \"production\"]\n| stats count(*) as events by kubernetes.namespace_name, kubernetes.container_name\n| sort events desc"
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 14
        width  = 12
        height = 7
        properties = {
          title  = "Recent application errors"
          region = var.aws_region
          view   = "table"
          query  = "SOURCE '${aws_cloudwatch_log_group.container_insights["application"].name}' | fields @timestamp, kubernetes.namespace_name, kubernetes.container_name, log\n| filter kubernetes.namespace_name in [\"staging\", \"production\"]\n| filter log like /(?i)(error|exception|failed|giving)/\n| sort @timestamp desc\n| limit 50"
        }
      },
    ]
  })
}
