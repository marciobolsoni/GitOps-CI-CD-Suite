###############################################################################
# CloudWatch Module — marciobolsoni.cloud
# Creates alarms, dashboards, and log metric filters for deployment
# monitoring and automated canary rollback triggering.
###############################################################################

locals {
  name_prefix = "${var.project}-${var.environment}"
  common_tags = merge(var.tags, {
    Module      = "cloudwatch"
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "Terraform"
  })
}

# ─────────────────────────────────────────────
# SNS Topic for Deployment Alerts
# ─────────────────────────────────────────────
resource "aws_sns_topic" "deployment_alerts" {
  name              = "${local.name_prefix}-deployment-alerts"
  kms_master_key_id = var.kms_key_arn

  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = length(var.alert_emails)
  topic_arn = aws_sns_topic.deployment_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_emails[count.index]
}

# ─────────────────────────────────────────────
# CloudWatch Alarms — Canary Rollback Triggers
# ─────────────────────────────────────────────

# 1. HTTP 5xx Error Rate
resource "aws_cloudwatch_metric_alarm" "http_5xx_rate" {
  alarm_name          = "${local.name_prefix}-http-5xx-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 1.0
  alarm_description   = "HTTP 5xx error rate exceeds 1% — triggers canary rollback"
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "error_rate"
    expression  = "errors/requests*100"
    label       = "5xx Error Rate (%)"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
      }
    }
  }

  metric_query {
    id = "requests"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
      }
    }
  }

  alarm_actions = [aws_sns_topic.deployment_alerts.arn]
  ok_actions    = [aws_sns_topic.deployment_alerts.arn]

  tags = merge(local.common_tags, {
    RollbackTrigger = "true"
    Severity        = "critical"
  })
}

# 2. P99 Latency
resource "aws_cloudwatch_metric_alarm" "p99_latency" {
  alarm_name          = "${local.name_prefix}-p99-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  extended_statistic  = "p99"
  threshold           = 2.0
  alarm_description   = "P99 response time exceeds 2 seconds — triggers canary rollback"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.deployment_alerts.arn]
  ok_actions    = [aws_sns_topic.deployment_alerts.arn]

  tags = merge(local.common_tags, {
    RollbackTrigger = "true"
    Severity        = "high"
  })
}

# 3. ECS CPU Utilization
resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  alarm_name          = "${local.name_prefix}-ecs-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 85.0
  alarm_description   = "ECS CPU utilization exceeds 85% — triggers canary rollback"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions = [aws_sns_topic.deployment_alerts.arn]
  ok_actions    = [aws_sns_topic.deployment_alerts.arn]

  tags = merge(local.common_tags, {
    RollbackTrigger = "true"
    Severity        = "high"
  })
}

# 4. ECS Memory Utilization
resource "aws_cloudwatch_metric_alarm" "ecs_memory" {
  alarm_name          = "${local.name_prefix}-ecs-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 90.0
  alarm_description   = "ECS memory utilization exceeds 90% — triggers canary rollback"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions = [aws_sns_topic.deployment_alerts.arn]
  ok_actions    = [aws_sns_topic.deployment_alerts.arn]

  tags = merge(local.common_tags, {
    RollbackTrigger = "true"
    Severity        = "high"
  })
}

# 5. ECS Task Health (Running Tasks Count)
resource "aws_cloudwatch_metric_alarm" "ecs_running_tasks" {
  alarm_name          = "${local.name_prefix}-ecs-running-tasks"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = var.min_running_tasks
  alarm_description   = "Running ECS tasks below minimum threshold — triggers canary rollback"
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions = [aws_sns_topic.deployment_alerts.arn]
  ok_actions    = [aws_sns_topic.deployment_alerts.arn]

  tags = merge(local.common_tags, {
    RollbackTrigger = "true"
    Severity        = "critical"
  })
}

# ─────────────────────────────────────────────
# CloudWatch Dashboard — Deployment Health
# ─────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "deployment" {
  dashboard_name = "${local.name_prefix}-deployment-health"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "## 🚀 marciobolsoni.cloud — Deployment Health Dashboard | Environment: **${var.environment}**"
        }
      },
      {
        type   = "alarm"
        x      = 0
        y      = 1
        width  = 24
        height = 2
        properties = {
          title  = "Canary Rollback Triggers"
          alarms = [
            aws_cloudwatch_metric_alarm.http_5xx_rate.arn,
            aws_cloudwatch_metric_alarm.p99_latency.arn,
            aws_cloudwatch_metric_alarm.ecs_cpu.arn,
            aws_cloudwatch_metric_alarm.ecs_memory.arn,
            aws_cloudwatch_metric_alarm.ecs_running_tasks.arn
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 3
        width  = 12
        height = 6
        properties = {
          title  = "HTTP Error Rate (%)"
          period = 60
          stat   = "Sum"
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", var.alb_arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 3
        width  = 12
        height = 6
        properties = {
          title  = "Response Time (P50/P99)"
          period = 60
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p50", label = "P50" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p99", label = "P99" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 9
        width  = 12
        height = 6
        properties = {
          title  = "ECS CPU & Memory Utilization"
          period = 60
          stat   = "Average"
          view   = "timeSeries"
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name, { label = "CPU %" }],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name, { label = "Memory %" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 9
        width  = 12
        height = 6
        properties = {
          title  = "Request Count & Running Tasks"
          period = 60
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum", label = "Requests" }],
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name, { stat = "Average", label = "Running Tasks" }]
          ]
        }
      }
    ]
  })
}
