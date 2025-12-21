# Polyglot Ecommerce Platform (Java/Python/AWS)

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![Coverage](https://img.shields.io/badge/observability-100%25-blue)

**A reference architecture for high-throughput, event-driven systems on AWS.**

## 🏗️ Architecture
This system demonstrates the **Transactional Outbox Pattern** (simulated) and **Distributed Tracing** across language boundaries.

```mermaid
graph LR
subgraph "Client Layer"
User([User])
end

    subgraph "EKS / LocalStack Cluster"
        direction TB
        
        API[Java Order Service]
        SQS[(AWS SQS)]
        Worker[Python Inventory Worker]
        DB[(AWS DynamoDB)]
        
        %% Observability Components
        Jaeger[Jaeger Tracing]
    end

    %% Application Flow
    User -- "POST /orders" --> API
    API -- "1. PutItem (CREATED)" --> DB
    API -- "2. SendMessage (w/ Trace Context)" --> SQS
    SQS -.-> Worker
    Worker -- "3. Poll & Extract Context" --> SQS
    Worker -- "4. UpdateItem (PROCESSED)" --> DB

    %% Telemetry Flow
    API -- "OTLP (gRPC)" --> Jaeger
    Worker -- "OTLP (HTTP)" --> Jaeger

    %% Styling
    style API fill:#bbf,stroke:#333,stroke-width:2px
    style Worker fill:#bfb,stroke:#333,stroke-width:2px
    style SQS fill:#faa,stroke:#333,stroke-width:2px
    style DB fill:#faa,stroke:#333,stroke-width:2px
    style Jaeger fill:#eee,stroke:#333,stroke-width:1px,stroke-dasharray: 5 5
```

## 🚀 Key Features
* **Polyglot Microservices:** Spring Boot 3 (Java 17) for high-concurrency ingestion; Python 3.10 for flexible background processing.
* **Event-Driven:** Decoupled architecture using **AWS SQS** for asynchronous communication.
* **End-to-End Observability:** Implements **OpenTelemetry** to trace requests from the Java API, through the SQS Queue, to the Python Worker.
    * *See [ADR-001](docs/adr/001-observability-strategy.md) for context propagation strategy.*
* **Infrastructure as Code:** Fully reproducible local environment using **LocalStack** and Docker Compose.

## 🛠️ Tech Stack
* **Compute:** Java 17 (Spring Boot), Python 3.10 (Boto3)
* **Data:** AWS DynamoDB, AWS SQS
* **Observability:** OpenTelemetry, Jaeger
* **DevOps:** Docker, LocalStack

## 🏃‍♂️ Quick Start

### 1. Infrastructure
```bash
docker-compose up -d
```
# **Local Cloud E-Commerce Environment**

This project simulates a full AWS microservices architecture locally using **Docker** and **LocalStack**.

## **📋 Prerequisites**

* Docker Desktop / Docker Engine
* curl (for testing APIs)

## **🚀 How to Run**

### **1\. Prepare the Environment**

Ensure the LocalStack initialization script is executable. This script automatically creates the SQS queues and DynamoDB tables when the container starts.  
``
chmod +x infra/localstack-init.sh
``
### **2\. Start the Services**

Use the docker-compose.local.yaml file to build the Java/Python images and start the local cloud emulator.  
``
docker-compose -f docker-compose.yml up --build
``
* **Wait** until you see the log message:  ✅ [IaC] Infrastructure provisioning complete.
* The **Java Inventory Service** will be available at http://localhost:8080.

### **3\. Test the Application**

Send a sample order to the Java service. This simulates an order ingestion event.  
``
curl -X POST http://localhost:8080/inventory-update \
  -H "Content-Type: application/json" \
  -d '{"sku": "LOCAL-TEST-SKU", "quantity": 10}'
``

**(Note: Use "LOCAL-TEST-SKU" as it was seeded with stock in the init script. Other SKUs may return "Insufficient stock" unless added.)**

### **4\. Verify Results**

Check the Logs:  
Watch the terminal where Docker is running. You should see:

1. **Inventory Service:** "Processing Order... Stock updated."
2. **Pricing Service:** "Received verified inventory event... Successfully persisted price change."

Check DynamoDB (Audit Log):  
You can query the local DynamoDB table directly to see the audit trail created by the Python service.  
Run this command (requires aws CLI or awslocal installed, or run inside the container):  
# Execute inside the running LocalStack container
``docker exec -it $(docker-compose -f docker-compose.local.yaml ps -q localstack) \
  awslocal dynamodb scan --table-name PriceHistory --region us-west-2
``
## **🛑 Stopping**

To stop the containers and remove the volumes (resetting the database):  
``docker exec -it $(docker-compose -f docker-compose.local.yaml ps -q localstack) \
awslocal dynamodb scan --table-name PriceHistory --region us-west-2
``

🛑 Stopping

To stop the containers and remove the volumes (resetting the database):

``
docker-compose -f docker-compose.local.yaml down -v  
``