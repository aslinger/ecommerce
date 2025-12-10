# ADR 001: Distributed Observability Strategy

* **Status:** Accepted
* **Date:** 2025-12-09
* **Context:**
  Our system decouples ingestion (Java) from processing (Python) via SQS.
  This introduces a "Blind Spot": standard APM tools lose the trace when the request hits the queue.
  We needed a way to visualize the full transaction lifecycle to reduce MTTR during latency incidents.

* **Decision:**
  We adopted **OpenTelemetry** for vendor-neutral instrumentation.

  **Specific Implementation:**
    1. **Java (Producer):** We utilize the **Manual Context Injection** pattern using `GlobalOpenTelemetry`.
        * *Why not Auto-Instrumentation?* During PoC, the auto-agent struggled to consistently inject headers into SQS Message Attributes when running against LocalStack. Manual injection provided 100% reliability for the critical path.
    2. **Python (Consumer):** We use the `opentelemetry-sdk` to manually extract the `traceparent` header from SQS Message Attributes.
    3. **Protocol:** OTLP (gRPC for Java, HTTP for Python) sending to a self-hosted Jaeger instance.

* **Consequences:**
    * **Positive:** We achieved 100% trace continuity. A single Trace ID now queries the entire lifecycle (API -> DB -> SQS -> Worker).
    * **Negative:** Small code footprint increased in `OrderController.java` to handle the manual injection logic.