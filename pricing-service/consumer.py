import boto3
import json
import time
import sys
import logging

# --- OPENTELEMETRY IMPORTS ---
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.propagate import extract
from opentelemetry.context import attach, detach

# --- CONFIGURATION ---
REGION = 'us-east-1'
ENDPOINT = 'http://localhost:4566'
QUEUE_URL = 'http://localhost:4566/000000000000/order-events'
TABLE_NAME = 'Orders'

# --- 1. SETUP OBSERVABILITY ---
# Define the Resource (Service Name)
resource = Resource(attributes={
    "service.name": "inventory-worker-python"
})

# Configure the Exporter (Send data to Jaeger on Port 4318)
trace.set_tracer_provider(TracerProvider(resource=resource))
tracer = trace.get_tracer(__name__)
otlp_exporter = OTLPSpanExporter(endpoint="http://localhost:4318/v1/traces")
trace.get_tracer_provider().add_span_processor(BatchSpanProcessor(otlp_exporter))

print(f"🚀 OBSERVABLE WORKER STARTED")
sqs = boto3.client('sqs', region_name=REGION, endpoint_url=ENDPOINT)
dynamodb = boto3.client('dynamodb', region_name=REGION, endpoint_url=ENDPOINT)

def process_message(body, receipt_handle, message_attributes):
    print(f"🧐 RAW ATTRIBUTES: {message_attributes}")

    # --- 2. EXTRACT CONTEXT (THE STAFF LOGIC) ---
    # The Java Agent injected 'traceparent' into the SQS Message Attributes.
    # We must extract it to link the spans.
    ctx = None
    if message_attributes:
        # Convert SQS Attribute format to a simple dict for OTel
        carrier = {}
        for key, value in message_attributes.items():
            if 'StringValue' in value:
                carrier[key] = value['StringValue']

        ctx = extract(carrier)

    # Start the span using the extracted parent context
    with tracer.start_as_current_span("process_order", context=ctx) as span:
        try:
            data = json.loads(body)
            order_id = data.get('orderId')

            span.set_attribute("app.order_id", order_id)
            print(f"   📦 Processing Order: {order_id} [Trace Linked!]")

            # Simulate work (this will show up as a long bar in Jaeger)
            time.sleep(1)

            # Update DynamoDB
            dynamodb.update_item(
                TableName=TABLE_NAME,
                Key={'orderId': {'S': order_id}},
                UpdateExpression="set #s = :status",
                ExpressionAttributeNames={'#s': 'status'},
                ExpressionAttributeValues={':status': {'S': 'PROCESSED'}}
            )
            print(f"   ✅ Updated DynamoDB")

            # Delete from Queue
            sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=receipt_handle)

        except Exception as e:
            print(f"   ❌ Error: {e}")
            span.record_exception(e)
            span.set_status(trace.Status(trace.StatusCode.ERROR))

def poll():
    print("👀 Polling for messages...")
    while True:
        try:
            response = sqs.receive_message(
                QueueUrl=QUEUE_URL,
                MaxNumberOfMessages=1,
                WaitTimeSeconds=5,
                MessageAttributeNames=['All'] # CRITICAL: Must request attributes to get the Trace ID
            )

            if 'Messages' in response:
                for msg in response['Messages']:
                    # Pass attributes to the processor
                    process_message(msg['Body'], msg['ReceiptHandle'], msg.get('MessageAttributes'))

        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"   ⚠️ Polling Error: {e}")
            time.sleep(2)

if __name__ == '__main__':
    poll()