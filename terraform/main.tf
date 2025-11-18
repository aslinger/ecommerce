#
# Day 1: Infrastructure Foundation (VPC, SQS, ECR)
# This file provisions the core networking, messaging, and container registry components.
#

# --- 1. AWS Provider Configuration ---
# You need to define the AWS provider and set your target region.
terraform {
  required_providers {
    aws = {
      source  = \"hashicorp/aws\"
      version = \"~> 5.0\"
    }
  }
}

variable \"aws_region\" {
  description = \"The AWS region to deploy resources into.\"
  type        = string
  # TODO: Update the default region to your preferred location (e.g., \"us-east-1\", \"eu-west-1\")
  default     = \"us-west-2\" 
}

provider \"aws\" {
  region = var.aws_region
}

# --- 2. VPC and Networking (Base for EKS) ---
# Using the community VPC module for a robust, multi-AZ network setup.
module \"vpc\" {
  source  = \"terraform-aws-modules/vpc/aws\"
  version = \"5.0.0\"

  name = \"ecommerce-eks-vpc\"
  cidr = \"10.0.0.0/16\"

  azs             = [\"${var.aws_region}a\", \"${var.aws_region}b\", \"${var.aws_region}c\"]
  private_subnets = [\"10.0.1.0/24\", \"10.0.2.0/24\", \"10.0.3.0/24\"]
  public_subnets  = [\"10.0.101.0/24\", \"10.0.102.0/24\", \"10.0.103.0/24\"]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  enable_dns_hostnames   = true
  enable_dns_support     = true

  tags = {
    # TODO: Add your name or identifier here
    \"Project\" = \"CloudNative-Ecomm\"
    \"Name\"    = \"EKS-VPC\"
  }
}

# Output VPC details needed for EKS configuration on Day 2
output \"vpc_id\" {
  description = \"The ID of the VPC.\"
  value       = module.vpc.vpc_id
}
output \"private_subnet_ids\" {
  description = \"List of IDs of private subnets.\"
  value       = module.vpc.private_subnets
}

# --- 3. SQS Queue Provisioning (Messaging) ---
# The queue for Java Inventory Service to send updates and Python/Go Pricing Service to consume.
resource \"aws_sqs_queue\" \"inventory_update_queue\" {
  name                      = \"inventory-update-queue\"
  delay_seconds             = 0
  max_message_size          = 262144
  message_retention_seconds = 86400
  visibility_timeout_seconds = 300 # 5 minutes for processing

  tags = {
    \"Service\" = \"InventoryMessaging\"
  }
}

# --- 4. ECR Repositories (Container Storage) ---
# Repositories for the two microservices.
resource \"aws_ecr_repository\" \"java_inventory_service_repo\" {
  name = \"java-inventory-service\"
  image_tag_mutability = \"MUTABLE\"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource \"aws_ecr_repository\" \"pricing_service_repo\" {
  name = \"pricing-service\"
  image_tag_mutability = \"MUTABLE\"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# --- 5. IAM Policy for SQS Access (Required for Day 2 IRSA) ---
# This policy defines the minimal permissions needed for the Pricing Service to consume SQS messages.
# We will attach this policy to the EKS Service Account Role on Day 2.
data \"aws_iam_policy_document\" \"sqs_consumer_policy\" {
  statement {
    sid = \"SQSConsumerAccess\"
    actions = [
      \"sqs:ReceiveMessage\",
      \"sqs:DeleteMessage\",
      \"sqs:GetQueueAttributes\",
    ]
    resources = [
      aws_sqs_queue.inventory_update_queue.arn,
    ]
  }
}

resource \"aws_iam_policy\" \"sqs_consumer_policy\" {
  name        = \"sqs-consumer-policy\"
  description = \"Minimal policy for pricing service to consume SQS messages.\"
  policy      = data.aws_iam_policy_document.sqs_consumer_policy.json
}

output \"sqs_queue_url\" {
  description = \"The URL of the SQS queue.\"
  value       = aws_sqs_queue.inventory_update_queue.id
}
output \"sqs_consumer_policy_arn\" {
  description = \"The ARN of the IAM policy for the SQS consumer.\"
  value       = aws_iam_policy.sqs_consumer_policy.arn
}

# TODO: After running 'terraform init' and 'terraform apply',
# verify the VPC, SQS queue, and ECR repos exist in the AWS Console.
