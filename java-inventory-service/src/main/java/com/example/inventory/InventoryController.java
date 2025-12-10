package com.example.inventory;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * REST Controller for inventory updates.
 * This service acts as the SQS Producer.
 */
@RestController
public class InventoryController {

    private static final Logger logger = LoggerFactory.getLogger(InventoryController.class);

    // SQS Queue URL will be injected via Kubernetes ConfigMap/Environment Variable on Day 4
    @Value("${sqs.queue.url}")
    private String sqsQueueUrl;

    // TODO: SqsClient bean must be configured in a separate Spring @Configuration class
    private final SqsClient sqsClient; 

    public InventoryController(SqsClient sqsClient) {
        this.sqsClient = sqsClient;
    }

    /**
     * Endpoint to simulate an inventory update, publishing a message to SQS.
     * @param inventoryData Map containing SKU and stock level (e.g., {"sku": "12345", "stock": 10})
     * @return 202 Accepted response.
     */
    @PostMapping("/inventory-update")
    public ResponseEntity<String> postInventoryUpdate(@RequestBody Map<String, Object> inventoryData) {
        if (sqsQueueUrl == null || sqsQueueUrl.isEmpty()) {
            logger.error("SQS Queue URL not configured. Check environment variables.");
            return ResponseEntity.internalServerError().body("Messaging system not ready.");
        }

        String messageBody = String.format("{\"sku\": \"%s\", \"stock\": %d}",
            inventoryData.get("sku"), 
            inventoryData.get("stock"));

        SendMessageRequest sendMsgRequest = SendMessageRequest.builder()
                .queueUrl(sqsQueueUrl)
                .messageBody(messageBody)
                .build();

        try {
            sqsClient.sendMessage(sendMsgRequest);
            logger.info("Successfully published inventory update message to SQS: {}", messageBody);

            return ResponseEntity.accepted().body("Inventory update queued successfully."); 
        } catch (Exception e) {
            logger.error("Failed to send message to SQS: {}", e.getMessage(), e);
            return ResponseEntity.internalServerError().body("Failed to queue inventory update.");
        }
    }
}