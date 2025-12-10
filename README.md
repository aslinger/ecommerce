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
# Waits for LocalStack (SQS/DynamoDB) and Jaeger to initialize