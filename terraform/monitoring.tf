data "aws_sqs_queue" "inventory_update_queue" {
  name = "inventory-update-queue"
}

resource "aws_sns_topic" "sqs_alert_topic" {
  name = "InventoryUpdateBacklogAlert"
}

resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.sqs_alert_topic.arn
  protocol  = "email"
  endpoint  = "john.a.aslinger@gmail.com"
}

resource "aws_cloudwatch_metric_alarm" "sqs_backlog_alarm" {
  alarm_name                = "HighSQSBacklogAlarm"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = 1
  metric_name               = "ApproximateNumberOfMessagesVisible"
  namespace                 = "AWS/SQS"
  period                    = 300
  statistic                 = "Average"
  threshold                 = 50

  dimensions = {
    QueueName = data.aws_sqs_queue.inventory_update_queue.name
  }

  alarm_description = "Alerts when the SQS message backlog exceeds 50, indicating a consumer processing issue."
  

  alarm_actions = [aws_sns_topic.sqs_alert_topic.arn]
  ok_actions    = [aws_sns_topic.sqs_alert_topic.arn]
  
  treat_missing_data = "notBreaching"
}

output "sqs_alert_topic_arn" {
  description = "The ARN of the SNS Topic for SQS Backlog Alerts."
  value       = aws_sns_topic.sqs_alert_topic.arn
}