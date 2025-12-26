package com.example.inventory;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.*;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Inventory Processor.
 * Roles:
 * 1. CONSUMER: Polls 'order-processing-queue'.
 * 2. STATE MANAGER: Checks/Decrements 'InventoryState' DynamoDB table.
 * 3. PRODUCER: Emits success events to 'inventory-price-update-events' queue.
 */
@Component
public class InventoryController implements CommandLineRunner {

    private static final Logger logger = LoggerFactory.getLogger(InventoryController.class);
    private final ObjectMapper objectMapper = new ObjectMapper();

    @Value("${sqs.order.queue.url}")
    private String orderQueueUrl;

    @Value("${sqs.price.update.queue.url}")
    private String priceUpdateQueueUrl;

    @Value("${dynamodb.inventory.table.name}")
    private String inventoryTableName;

    private final SqsClient sqsClient;
    private final DynamoDbClient dynamoDbClient;

    public InventoryController(SqsClient sqsClient, DynamoDbClient dynamoDbClient) {
        this.sqsClient = sqsClient;
        this.dynamoDbClient = dynamoDbClient;
    }

    @Override
    public void run(String... args) {
        logger.info("Starting Inventory Processor...");
        logger.info("Polling Order Queue: {}", orderQueueUrl);
        logger.info("Publishing to Price Queue: {}", priceUpdateQueueUrl);
        logger.info("Managing Inventory Table: {}", inventoryTableName);

        while (true) {
            try {
                ReceiveMessageRequest receiveRequest = ReceiveMessageRequest.builder()
                        .queueUrl(orderQueueUrl)
                        .maxNumberOfMessages(10)
                        .waitTimeSeconds(20) // Long polling
                        .build();

                List<Message> messages = sqsClient.receiveMessage(receiveRequest).messages();

                for (Message message : messages) {
                    processOrder(message);

                    sqsClient.deleteMessage(DeleteMessageRequest.builder()
                            .queueUrl(orderQueueUrl)
                            .receiptHandle(message.receiptHandle())
                            .build());
                }
            } catch (Exception e) {
                logger.error("Error in processing loop: {}", e.getMessage());
                try { Thread.sleep(5000); } catch (InterruptedException ignored) {}
            }
        }
    }

    private void processOrder(Message message) {
        try {
            JsonNode json = objectMapper.readTree(message.body());
            String sku = json.has("sku") ? json.get("sku").asText() : "UNKNOWN";
            int quantity = json.has("quantity") ? json.get("quantity").asInt() : 1;

            logger.info("Processing Order for SKU: {}", sku);

            // 1. Transactional Stock Check & Decrement
            int newStockLevel = updateStockInDB(sku, quantity);

            if (newStockLevel >= 0) {
                // 2. Publish Event to Price Queue (Success)
                String eventBody = String.format("{\"sku\": \"%s\", \"stock\": %d, \"source\": \"inventory-processor\"}", sku, newStockLevel);

                sqsClient.sendMessage(SendMessageRequest.builder()
                        .queueUrl(priceUpdateQueueUrl)
                        .messageBody(eventBody)
                        .build());
                logger.info("Stock updated. Event published for SKU: {}", sku);
            } else {
                logger.warn("Insufficient stock for SKU: {}", sku);
            }

        } catch (Exception e) {
            logger.error("Failed to process message: {}", message.body(), e);
        }
    }

    private int updateStockInDB(String sku, int quantity) {
        try {
            Map<String, AttributeValue> key = new HashMap<>();
            key.put("SKU", AttributeValue.builder().s(sku).build());

            Map<String, AttributeValue> expressionValues = new HashMap<>();
            expressionValues.put(":dec", AttributeValue.builder().n(String.valueOf(quantity)).build());

            UpdateItemRequest request = UpdateItemRequest.builder()
                    .tableName(inventoryTableName)
                    .key(key)
                    .updateExpression("SET Stock = Stock - :dec")
                    .conditionExpression("Stock >= :dec")
                    // FIX: This line was missing, causing the "value not defined" error
                    .expressionAttributeValues(expressionValues)
                    .returnValues(ReturnValue.UPDATED_NEW)
                    .build();

            UpdateItemResponse response = dynamoDbClient.updateItem(request);
            return Integer.parseInt(response.attributes().get("Stock").n());

        } catch (ConditionalCheckFailedException e) {
            logger.warn("Conditional check failed (Out of Stock) for SKU: {}", sku);
            return -1;
        } catch (Exception e) {
            logger.error("DynamoDB Error for SKU {}: {}", sku, e.getMessage());
            return -1;
        }
    }
}