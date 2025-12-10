package com.example.inventory;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.propagation.TextMapSetter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
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

    @Value("${aws.table-name}")
    private String tableName;

    @Value("${aws.queue-url}")
    private String queueUrl;

    public OrderController(DynamoDbClient dynamoDbClient, SqsClient sqsClient) {
        this.dynamoDbClient = dynamoDbClient;
        this.sqsClient = sqsClient;
    }

    @PostMapping("/orders")
    public String createOrder(@RequestBody OrderRequest request) {
        String orderId = UUID.randomUUID().toString();
        log.info("Processing order: {}", orderId);

        // 1. Save to DynamoDB
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

        // 2. PREPARE SQS ATTRIBUTES (Context Injection)
        Map<String, MessageAttributeValue> messageAttributes = new HashMap<>();

        // This injector puts "traceparent" into the map
        GlobalOpenTelemetry.getPropagators().getTextMapPropagator().inject(
                Context.current(),
                messageAttributes,
                setter
        );

        // 3. Publish to SQS
        sqsClient.sendMessage(SendMessageRequest.builder()
                .queueUrl(queueUrl)
                .messageBody("{\"orderId\": \"" + orderId + "\", \"action\": \"PROCESS\"}")
                .messageAttributes(messageAttributes) // <--- Attach the trace here
                .build());

        log.info("Published to SQS with Trace Context");
        return orderId;
    }

    // Setter tells OTEL how to put data into the AWS SDK Map
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
    @Value("${aws.endpoint}")
    private String endpoint;
    @Value("${aws.region}")
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