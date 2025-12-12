#!/bin/bash
set -e

echo "🚀 [IaC] Initializing LocalStack resources..."

REGION="us-west-2"

TABLE_NAME="Orders"
QUEUE_NAME="order-events"
DLQ_NAME="order-events-dlq"

echo "Creating DynamoDB Table: $TABLE_NAME..."
awslocal dynamodb create-table \
    --table-name $TABLE_NAME \
    --attribute-definitions AttributeName=orderId,AttributeType=S \
    --key-schema AttributeName=orderId,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION

echo "Creating DLQ: $DLQ_NAME..."
DLQ_URL=$(awslocal sqs create-queue --queue-name $DLQ_NAME --region $REGION --output text --query QueueUrl)
DLQ_ARN=$(awslocal sqs get-queue-attributes --queue-url $DLQ_URL --attribute-names QueueArn --output text --query Attributes.QueueArn)

echo "Creating Main Queue: $QUEUE_NAME..."
awslocal sqs create-queue \
    --queue-name $QUEUE_NAME \
    --region $REGION \
    --attributes "{\"RedrivePolicy\": \"{\\\"deadLetterTargetArn\\\":\\\"$DLQ_ARN\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"}"

echo "Creating Queue: inventory-update-queue (Internal Messaging)"
awslocal sqs create-queue \
  --queue-name inventory-update-queue \
  --region $REGION

echo "Creating Queue: order-processing-queue (Order Ingestion)"
awslocal sqs create-queue \
  --queue-name order-processing-queue \
  --region $REGION

echo "Creating DynamoDB Table: PriceHistory (Audit Log)"
awslocal dynamodb create-table \
  --table-name PriceHistory \
  --attribute-definitions \
    AttributeName=SKU,AttributeType=S \
    AttributeName=Timestamp,AttributeType=S \
  --key-schema \
    AttributeName=SKU,KeyType=HASH \
    AttributeName=Timestamp,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST \
  --region $REGION

echo "Creating DynamoDB Table: InventoryState (Stock Levels)"
awslocal dynamodb create-table \
  --table-name InventoryState \
  --attribute-definitions \
    AttributeName=SKU,AttributeType=S \
  --key-schema \
    AttributeName=SKU,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $REGION

echo "Seeding InventoryState with initial stock..."
awslocal dynamodb put-item \
    --table-name InventoryState \
    --item '{"SKU": {"S": "LOCAL-TEST-SKU"}, "Stock": {"N": "100"}}' \
    --region $REGION

echo "✅ [IaC] Infrastructure provisioning complete."