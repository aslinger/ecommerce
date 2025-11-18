#
# Day 6: Monitoring and Alerting
# This file provisions an SNS Topic and a CloudWatch Alarm to monitor the SQS queue backlog,
# ensuring production readiness and observability.
#

# --- 1. SQS Queue Reference ---
# We need to reference the SQS queue provisioned in main.tf to set up the alarm.
data \"aws_sqs_queue\" \"inventory_update_queue\" {
  name = \"inventory-update-queue\"
}

# --- 2. SNS Topic for Alerts ---
# The target for our CloudWatch alarm actions.
resource \"aws_sns_topic\" \"sqs_alert_topic\" {
  name = \"InventoryUpdateBacklogAlert\"
}

# SNS Topic subscription (e.g., email notification)
# NOTE: This email address will need to be confirmed via the subscription email.
resource \"aws_sns_topic_subscription\" \"email_subscription\" {
  topic_arn = aws_sns_topic.sqs_alert_topic.arn
  protocol  = \"email\"
  # TODO: Replace with your actual email address for testing alerts
  endpoint  = \"your.name@example.com\" 
}

# --- 3. CloudWatch Metric Alarm (Backlog Monitoring) ---
# Alarm fires when the number of visible messages in the queue (backlog) exceeds a threshold.
resource \"aws_cloudwatch_metric_alarm\" \"sqs_backlog_alarm\" {
  alarm_name                = \"HighSQSBacklogAlarm\"
  comparison_operator       = \"GreaterThanThreshold\"
  evaluation_periods        = 1
  metric_name               = \"ApproximateNumberOfMessagesVisible\"
  namespace                 = \"AWS/SQS\"
  period                    = 300 # 5 minutes
  statistic                 = \"Average\"
  threshold                 = 50 # Alarm if backlog exceeds 50 messages for 5 minutes

  dimensions = {
    QueueName = data.aws_sqs_queue.inventory_update_queue.name
  }

  alarm_description = \"Alerts when the SQS message backlog exceeds 50, indicating a consumer processing issue.\"
  
  # Action to take when the alarm state is reached
  alarm_actions = [aws_sns_topic.sqs_alert_topic.arn]
  
  # Action to take when the alarm returns to OK state
  ok_actions    = [aws_sns_topic.sqs_alert_topic.arn]
  
  treat_missing_data = \"notBreaching\"
}

# --- 4. Output the Alerting Resource ARN ---
output \"sqs_alert_topic_arn\" {
  description = \"The ARN of the SNS Topic for SQS Backlog Alerts.\"
  value       = aws_sns_topic.sqs_alert_topic.arn
}