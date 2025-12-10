#!/bin/bash
set -e

echo "🚀 [IaC] Initializing LocalStack resources..."

# 1. Define Variables
REGION="us-east-1"
TABLE_NAME="Orders"
QUEUE_NAME="order-events"
DLQ_NAME="order-events-dlq"

# 2. Create DynamoDB Table
echo "Creating DynamoDB Table: $TABLE_NAME..."
awslocal dynamodb create-table \
    --table-name $TABLE_NAME \
    --attribute-definitions AttributeName=orderId,AttributeType=S \
    --key-schema AttributeName=orderId,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION

# 3. Create Dead Letter Queue (DLQ) - Staff Level Move
echo "Creating DLQ: $DLQ_NAME..."
DLQ_URL=$(awslocal sqs create-queue --queue-name $DLQ_NAME --region $REGION --output text --query QueueUrl)
DLQ_ARN=$(awslocal sqs get-queue-attributes --queue-url $DLQ_URL --attribute-names QueueArn --output text --query Attributes.QueueArn)

# 4. Create Main Queue with Redrive Policy
echo "Creating Main Queue: $QUEUE_NAME..."
awslocal sqs create-queue \
    --queue-name $QUEUE_NAME \
    --region $REGION \
    --attributes "{\"RedrivePolicy\": \"{\\\"deadLetterTargetArn\\\":\\\"$DLQ_ARN\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"}"

echo "✅ [IaC] Infrastructure provisioning complete."