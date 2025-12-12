import os
import time
import json
import logging
import boto3
from botocore.exceptions import ClientError
from decimal import Decimal

SQS_QUEUE_URL = os.environ.get("SQS_PRICE_UPDATE_QUEUE_URL")
REGION_NAME = os.environ.get("AWS_REGION", "us-east-1")
DYNAMODB_TABLE_NAME = os.environ.get("DYNAMODB_TABLE_NAME")

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def get_boto_clients():
    """Initializes Boto3 clients. Relies on IRSA for credentials."""
    sqs_client = boto3.client('sqs', region_name=REGION_NAME)
    dynamodb_client = boto3.client('dynamodb', region_name=REGION_NAME)
    return sqs_client, dynamodb_client

def process_message(message_body, dynamodb_client):
    """
    Simulates dynamic pricing logic and writes the result to DynamoDB.
    """
    logging.info(f"Received verified inventory event.")

    try:
        data = json.loads(message_body)
        sku = data.get("sku")
        stock = Decimal(data.get("stock", 0))

        if not sku:
            logging.warning("Message missing SKU.")
            return

        price_change_reason = ""
        if stock < 10:
            price_change_reason = "INCREASED by 15% (Critical Low Stock)"
        elif stock > 50:
            price_change_reason = "DECREASED by 5% (High Stock/Overstock)"
        else:
            price_change_reason = "UNCHANGED (Normal Stock)"

        logging.info(f"--> [Pricing Engine] SKU {sku} (Current Stock: {stock}): Price {price_change_reason}")

        if not DYNAMODB_TABLE_NAME:
            logging.warning("DYNAMODB_TABLE_NAME not set. Skipping persistence.")
            return

        timestamp = str(int(time.time()))

        dynamodb_client.put_item(
            TableName=DYNAMODB_TABLE_NAME,
            Item={
                'SKU': {'S': sku},
                'Timestamp': {'S': timestamp},
                'StockLevel': {'N': str(stock)},
                'PriceChangeReason': {'S': price_change_reason},
                'MessageBody': {'S': message_body} # Audit log
            }
        )
        logging.info(f"Successfully persisted price change for SKU {sku} to DynamoDB.")

    except json.JSONDecodeError:
        logging.error(f"Error decoding JSON message: {message_body}")
    except ClientError as e:
        logging.error(f"Boto3 ClientError persisting to DynamoDB: {e.response['Error']['Code']}")
    except Exception as e:
        logging.error(f"Error in processing: {e}")


def consume_messages(sqs_client, dynamodb_client):
    """Polls the SQS queue continuously using long polling."""
    if not SQS_QUEUE_URL:
        logging.error("SQS_PRICE_UPDATE_QUEUE_URL environment variable is not set. Cannot start consumer.")
        return

    logging.info(f"Starting SQS consumer, polling: {SQS_QUEUE_URL}...")

    while True:
        try:
            response = sqs_client.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                AttributeNames=['All'],
                MaxNumberOfMessages=10,
                WaitTimeSeconds=20
            )

            messages = response.get('Messages', [])

            if messages:
                for message in messages:
                    # Pass DynamoDB client to processing function
                    process_message(message['Body'], dynamodb_client)

                    sqs_client.delete_message(
                        QueueUrl=SQS_QUEUE_URL,
                        ReceiptHandle=message['ReceiptHandle']
                    )
                    logging.info("Message processed and deleted from SQS.")

            time.sleep(1)

        except ClientError as e:
            error_code = e.response.get('Error', {}).get('Code', 'Unknown')
            logging.error(f"AWS Client Error (SQS): {error_code} - Check IRSA configuration.")
            time.sleep(30)
        except Exception as e:
            logging.error(f"An unexpected runtime error occurred: {e}")
            time.sleep(10)


if __name__ == '__main__':
    sqs_client, dynamodb_client = get_boto_clients()
    consume_messages(sqs_client, dynamodb_client)