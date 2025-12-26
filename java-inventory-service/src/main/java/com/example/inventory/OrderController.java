package com.example.inventory;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.propagation.TextMapSetter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.MessageAttributeValue;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;

import java.net.URI;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

@RestController
public class OrderController {

    private static final Logger log = LoggerFactory.getLogger(OrderController.class);
    private final DynamoDbClient dynamoDbClient;
    private final SqsClient sqsClient;

    @Value("${dynamodb.inventory.table.name}")
    private String tableName;

    @Value("${sqs.order.queue.url}")
    private String queueUrl;

    public OrderController(DynamoDbClient dynamoDbClient, SqsClient sqsClient) {
        this.dynamoDbClient = dynamoDbClient;
        this.sqsClient = sqsClient;
    }

    @PostMapping("/inventory-update")
    public ResponseEntity<String> createOrder(@RequestBody Map<String, Object> orderData) {
        String sku = (String) orderData.get("sku");
        Object qtyObj = orderData.get("quantity");
        int quantity = (qtyObj instanceof Integer) ? (Integer) qtyObj : 1;

        log.info("Received API Order Request: {} x {}", quantity, sku);

        try {
            String messageBody = String.format("{\"sku\": \"%s\", \"quantity\": %d}", sku, quantity);

            sqsClient.sendMessage(SendMessageRequest.builder()
                    .queueUrl(queueUrl)
                    .messageBody(messageBody)
                    .build());

            log.info("Order successfully queued.");
            return ResponseEntity.accepted().body("Order queued for processing.");

        } catch (Exception e) {
            // FIXED: Using 'log'
            log.error("Failed to queue order", e);
            return ResponseEntity.internalServerError().body("Failed to process order ingestion.");
        }
    }

    @PostMapping("/orders")
    public String createOrder(@RequestBody OrderRequest request) {
        String orderId = UUID.randomUUID().toString();
        log.info("Processing order: {}", orderId);

        Map<String, AttributeValue> item = Map.of(
                "orderId", AttributeValue.builder().s(orderId).build(),
                "item", AttributeValue.builder().s(request.getItem()).build(),
                "price", AttributeValue.builder().n(String.valueOf(request.getPrice())).build(),
                "status", AttributeValue.builder().s("CREATED").build()
        );

        dynamoDbClient.putItem(PutItemRequest.builder()
                .tableName(tableName)
                .item(item)
                .build());

        Map<String, MessageAttributeValue> messageAttributes = new HashMap<>();

        GlobalOpenTelemetry.getPropagators().getTextMapPropagator().inject(
                Context.current(),
                messageAttributes,
                setter
        );

        sqsClient.sendMessage(SendMessageRequest.builder()
                .queueUrl(queueUrl)
                .messageBody("{\"orderId\": \"" + orderId + "\", \"action\": \"PROCESS\"}")
                .messageAttributes(messageAttributes)
                .build());

        log.info("Published to SQS with Trace Context");
        return orderId;
    }

    private static final TextMapSetter<Map<String, MessageAttributeValue>> setter =
            (carrier, key, value) -> carrier.put(key, MessageAttributeValue.builder()
                    .dataType("String")
                    .stringValue(value)
                    .build());

    public static class OrderRequest {
        private String item;
        private double price;
        public String getItem() { return item; }
        public void setItem(String item) { this.item = item; }
        public double getPrice() { return price; }
        public void setPrice(double price) { this.price = price; }
    }
}

@Configuration
class AwsConfig {
    @Value("${AWS_ENDPOINT_URL:}")
    private String endpoint;

    @Value("${AWS_REGION:us-west-2}")
    private String region;

    @Bean
    public DynamoDbClient dynamoDbClient() {
        return DynamoDbClient.builder()
                .endpointOverride(URI.create(endpoint))
                .region(Region.of(region))
                .credentialsProvider(StaticCredentialsProvider.create(AwsBasicCredentials.create("test", "test")))
                .build();
    }

    @Bean
    public SqsClient sqsClient() {
        return SqsClient.builder()
                .endpointOverride(URI.create(endpoint))
                .region(Region.of(region))
                .credentialsProvider(StaticCredentialsProvider.create(AwsBasicCredentials.create("test", "test")))
                .build();
    }
}