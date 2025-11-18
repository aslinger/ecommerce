import os
import time
import json
import logging
import boto3
from botocore.exceptions import ClientError

# --- Configuration ---
# The SQS_QUEUE_URL will be injected via a Kubernetes ConfigMap/Environment Variable on Day 4.
SQS_QUEUE_URL = os.environ.get(\"SQS_QUEUE_URL\")
REGION_NAME = os.environ.get(\"AWS_REGION\", \"us-west-2\") # Matches the region defined in main.tf

# Logging setup
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def get_sqs_client():
    \"\"\"Initializes the SQS client. Relies on IRSA for credential lookup.\"\"\"
    # Since the service account (IRSA) has SQS permissions, boto3 automatically handles authentication.
    return boto3.client('sqs', region_name=REGION_NAME)

def process_message(message_body):
    \"\"\"
    Simulates the dynamic pricing logic based on the inventory update.
    \"\"\"
    logging.info(f\"Received message for processing.\")
    
    try:
        data = json.loads(message_body)
        sku = data.get(\"sku\")
        stock = data.get(\"stock\")
        
        # --- Dynamic Pricing Logic Simulation ---
        if stock is None:
            logging.warning(f\"Message for SKU {sku} missing stock level.\")
            return

        if stock < 10:
            price_change = \"INCREASED by 15% (Critical Low Stock)\"
        elif stock > 50:
            price_change = \"DECREASED by 5% (High Stock/Overstock)\"
        else:
            price_change = \"UNCHANGED (Normal Stock)\"
            
        logging.info(f\"--> [Pricing Engine] SKU {sku} (Stock: {stock}): Price {price_change}\")
        # In a production environment, this would trigger an update to a Pricing Database.

    except json.JSONDecodeError:
        logging.error(f\"Error decoding JSON message: {message_body}\")
    except Exception as e:
        logging.error(f\"Error in processing: {e}\")


def consume_messages(sqs_client):
    \"\"\"Polls the SQS queue continuously using long polling.\"\"\"
    if not SQS_QUEUE_URL:
        logging.error(\"SQS_QUEUE_URL environment variable is not set. Cannot start consumer.\")
        return

    logging.info(f\"Starting SQS consumer, polling: {SQS_QUEUE_URL}...\")

    while True:
        try:
            # WaitTimeSeconds=20 enables SQS long polling, improving cost and latency
            response = sqs_client.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                AttributeNames=['All'],
                MaxNumberOfMessages=10,
                WaitTimeSeconds=20 
            )

            messages = response.get('Messages', [])

            if messages:
                for message in messages:
                    process_message(message['Body'])
                    
                    # Delete the message after successful processing (at-least-once guarantee)
                    sqs_client.delete_message(
                        QueueUrl=SQS_QUEUE_URL,
                        ReceiptHandle=message['ReceiptHandle']
                    )
                    logging.info(\"Message processed and deleted.\")
            
            # Brief pause to avoid aggressive CPU usage if polling is very fast
            time.sleep(1) 

        except ClientError as e:
            # Log AWS-specific errors (e.g., permission denied)
            error_code = e.response.get('Error', {}).get('Code', 'Unknown')
            logging.error(f\"AWS Client Error: {error_code} - Check IRSA configuration.\")
            time.sleep(30)
        except Exception as e:
            logging.error(f\"An unexpected runtime error occurred: {e}\")
            time.sleep(10)


if __name__ == '__main__':
    # Initialize the SQS client
    sqs_client = get_sqs_client()
    consume_messages(sqs_client)
