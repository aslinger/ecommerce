# Cloud-Native E-Commerce Inventory & Pricing Platform

## Project Overview

This project implements a highly available, event-driven microservices architecture on AWS using Infrastructure as Code (IaC) principles. It simulates a core e-commerce workflow: processing inventory changes and triggering dynamic pricing updates.

The core objective was to demonstrate senior-level proficiency in polyglot application design, serverless container orchestration (EKS Fargate), full-stack automation (CI/CD), security best practices (Least Privilege), and cloud cost optimization.

---

## 💻 Technology Stack & Architecture

| Category | Technology | Purpose |
| :--- | :--- | :--- |
| **Cloud Infrastructure** | AWS | Core cloud provider. |
| **IaC** | Terraform (v5.x) | Provisioning of all AWS resources (VPC, EKS, SQS, ECR, CodePipeline, IAM, CloudWatch). |
| **Container Orchestration** | AWS EKS Fargate | Serverless Kubernetes compute plane, ensuring zero management overhead for underlying nodes. |
| **Microservices (Polyglot)** | Java (Spring Boot) | **Producer:** Inventory API service, responsible for receiving updates and publishing messages. |
| **Microservices (Polyglot)** | Python (Boto3) | **Consumer:** Dynamic Pricing Service, responsible for consuming SQS messages and simulating pricing logic. |
| **Messaging** | AWS SQS | Decouples the Inventory Producer from the Pricing Consumer, enabling asynchronous, event-driven communication. |

### Architecture Flow

1.  An API call is made to the **Java Inventory Service** (running on EKS Fargate).
2.  The Java service acts as an SQS **Producer**, queuing a message with the inventory update details.
3.  The message enters the AWS SQS queue (`inventory-update-queue`).
4.  The **Python Pricing Service** (running on EKS Fargate Spot) acts as the SQS **Consumer**, polling the queue using the Boto3 SDK.
5.  The Python service processes the message, logs the simulated pricing change, and deletes the message from the queue.

---

## 🛠️ DevOps Maturity & CI/CD Pipeline

The entire solution leverages a fully automated CI/CD pipeline orchestrated by Terraform, connecting a Git repository to the EKS cluster.

### AWS CodePipeline Stages:

1.  **Source:** Uses an AWS CodeStar Connection to securely pull code from GitHub on every push to the `main` branch.
2.  **Build:** Triggers an AWS CodeBuild project defined by a single `buildspec.yml`.
    * Authenticates to ECR.
    * Builds the **Java** Docker image.
    * Builds the **Python** Docker image.
    * Pushes both polyglot images to their respective ECR repositories.
    * Generates `imagedefinitions.json` and bundles K8s manifests for deployment.
3.  **Deploy:** Uses the specialized CodePipeline EKS action to apply the necessary Kubernetes manifests (Deployment, Service, ConfigMap) to the EKS cluster, triggering Fargate to pull the new container images.

---

## ⭐ Senior-Level Features & Optimization

### 1. Cost Optimization (Fargate Spot)

To demonstrate efficient resource management and reduce total cost of ownership (TCO), the EKS Fargate Profile was configured to utilize the **FARGATE_SPOT** capacity provider.

* **Impact:** Achieves up to **70% cost savings** on compute resources for the Python Pricing Service (which is an interruptible, asynchronous workload), drastically improving the solution’s budget efficiency.

### 2. Security (IRSA - Least Privilege)

Identity and Access Management (IAM) permissions were granted using **IAM Roles for Service Accounts (IRSA)**.

* **Implementation:** The Python Pricing Service runs under a dedicated Kubernetes Service Account, which is annotated with an IAM role that holds *only* the minimum necessary permissions (`sqs:ReceiveMessage`, `sqs:DeleteMessage`, etc.). This adheres strictly to the **principle of least privilege**.

### 3. Production Monitoring & Alerting

A critical production-readiness layer was added using AWS monitoring tools.

* **Implementation:** Terraform provisioned an **AWS CloudWatch Metric Alarm** that monitors the `ApproximateNumberOfMessagesVisible` metric on the SQS queue.
* **Alerting:** If the queue backlog exceeds a predefined threshold (50 messages) for a sustained period (5 minutes), an alert is sent via an **SNS Topic**, notifying the team of potential consumer failure or service degradation.

---

## 📝 High-Impact Resume Bullet Points

Use these quantifiable achievements to enhance the \"Independent Consulting/Project\" section on your resume, directly addressing Cloud, DevOps, and Seniority gaps.

* **Cloud Architecture & Polyglot:** Architected and deployed a multi-language (Java, Python) event-driven microservice platform on **AWS EKS Fargate**, utilizing SQS for asynchronous decoupling and demonstrating expertise in modern serverless container orchestration.
* **DevOps & Automation:** Developed a complete, 100% IaC CI/CD pipeline using **Terraform, AWS CodePipeline, and CodeBuild**, achieving zero-touch deployment of polyglot containers from Git to Kubernetes.
* **Cost Optimization & Efficiency:** Engineered the EKS Fargate infrastructure to leverage **Fargate Spot capacity** for asynchronous workloads, projected to achieve up to **70% cost savings** compared to standard on-demand compute.
* **Security & Observability:** Implemented **IRSA** (Least Privilege) for secure SQS access and integrated production-ready observability via a **CloudWatch Alarm** monitoring SQS backlog, with notifications routed through SNS, ensuring high service reliability.
