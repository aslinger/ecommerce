terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region" {
  description = "The AWS region to deploy resources into."
  type        = string
  default     = "us-west-2"
}

provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "ecommerce-eks-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    "Project" = "CloudNative-Ecomm"
    "Name"    = "EKS-VPC"
  }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

resource "aws_sqs_queue" "order_processing_queue" {
  name                       = "order-processing-queue"
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 86400
  visibility_timeout_seconds = 300
  tags = {
    "Purpose" = "Order_Ingestion"
  }
}

resource "aws_sqs_queue" "inventory_update_queue" {
  name                       = "inventory-price-update-events"
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 86400
  visibility_timeout_seconds = 300
  tags = {
    "Purpose" = "Price_Update_Events"
  }
}

resource "aws_ecr_repository" "java_inventory_service_repo" {
  name = "java-inventory-service"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "pricing_service_repo" {
  name = "pricing-service"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_dynamodb_table" "inventory_state" {
  name           = "InventoryState"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "SKU"

  attribute {
    name = "SKU"
    type = "S"
  }

  tags = {
    "Purpose" = "Inventory_State"
  }
}

resource "aws_dynamodb_table" "price_history" {
  name           = "PriceHistory"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "SKU"
  range_key      = "Timestamp"

  attribute {
    name = "SKU"
    type = "S"
  }

  attribute {
    name = "Timestamp"
    type = "S"
  }

  tags = {
    "Purpose" = "Price_Audit_Log"
  }
}

data "aws_iam_policy_document" "service_access_policy" {

  statement {
    sid = "SQSOrderIngestionAccess"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [
      aws_sqs_queue.order_processing_queue.arn,
    ]
  }

  statement {
    sid = "SQSPriceUpdateProducer"
    actions = [
      "sqs:SendMessage",
    ]
    resources = [
      aws_sqs_queue.inventory_update_queue.arn,
    ]
  }

  statement {
    sid = "DynamoDBInventoryStateRW"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:PutItem",
    ]
    resources = [
      aws_dynamodb_table.inventory_state.arn,
    ]
  }

  statement {
    sid = "DynamoDBPriceHistoryWrite"
    actions = [
      "dynamodb:PutItem"
    ]
    resources = [
      aws_dynamodb_table.price_history.arn,
    ]
  }

  statement {
    sid = "SQSPriceUpdateConsumer"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [
      aws_sqs_queue.inventory_update_queue.arn,
    ]
  }
}

resource "aws_iam_policy" "service_access_policy" {
  name   = "eks-service-access-policy"
  description = "Policy granting access to all SQS and DynamoDB resources for EKS services."
  policy = data.aws_iam_policy_document.service_access_policy.json
}

# --- 9. Outputs ---
output "sqs_order_queue_url" {
  description = "URL for the order processing queue (Input for Java)."
  value       = aws_sqs_queue.order_processing_queue.id
}
output "sqs_price_update_queue_url" {
  description = "URL for the price update events queue (Output from Java, Input for Python)."
  value       = aws_sqs_queue.inventory_update_queue.id
}
output "dynamodb_inventory_table_name" {
  description = "Name of the InventoryState DynamoDB table."
  value       = aws_dynamodb_table.inventory_state.name
}
output "dynamodb_price_history_table_name" {
  description = "Name of the PriceHistory DynamoDB table."
  value       = aws_dynamodb_table.price_history.name
}
output "service_access_policy_arn" {
  description = "The ARN of the combined IAM policy for all service access."
  value       = aws_iam_policy.service_access_policy.arn
}