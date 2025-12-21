#!/bin/bash
set -e

echo "🚀 [IaC] Initializing LocalStack resources..."

REGION="us-east-1"
TABLE_NAME="Orders"
QUEUE_NAME="order-events"
DLQ_NAME="order-events-dlq"
  
  # Create DynamoDB Table
echo "Creating DynamoDB Table $TABLE_NAME..."
awslocal dynamodb create-table \
--table-name "$TABLE_NAME" \
--attribute-definitions AttributeName=orderId,AttributeType=S \
--key-schema AttributeName=orderId,KeyType=HASH \
--billing-mode PAY_PER_REQUEST \
--region "$REGION"
  
  # Create Queues
echo "Creating DLQ $DLQ_NAME..."
DLQ_URL=$(awslocal sqs create-queue --queue-name "$DLQ_NAME" --region "$REGION" --output text --query QueueUrl)
DLQ_ARN=$(awslocal sqs get-queue-attributes --queue-url "$DLQ_URL" --attribute-names QueueArn --output text --query Attributes.QueueArn)

echo "Creating Main Queue $QUEUE_NAME..."
  # Note: No spaces after colons to prevent potential YAML parser false-positives
REDRIVE_POLICY="{\"deadLetterTargetArn\":\"$DLQ_ARN\",\"maxReceiveCount\":\"3\"}"
awslocal sqs create-queue \
--queue-name "$QUEUE_NAME" \
--region "$REGION" \
--attributes RedrivePolicy="$REDRIVE_POLICY"
  
  # Seeding Data
echo "Seeding InventoryState..."
ITEM_DATA="{\"SKU\":{\"S\":\"LOCAL-TEST-SKU\"},\"Stock\":{\"N\":\"100\"}}"
awslocal dynamodb put-item \
--table-name InventoryState \
--item "$ITEM_DATA" \
--region "$REGION"

echo "✅ [IaC] Infrastructure provisioning complete."
