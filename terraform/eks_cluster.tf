#
# Day 2: EKS Cluster Provisioning and IRSA Setup
# This file provisions the EKS control plane, Fargate profile, and the IAM role 
# required for the Pricing Service to securely access SQS via IRSA.
#

# --- 1. Load Outputs from main.tf ---
# These are the necessary variables created on Day 1.
locals {
  vpc_id                   = module.vpc.vpc_id
  private_subnet_ids       = module.vpc.private_subnets
  sqs_consumer_policy_arn  = aws_iam_policy.sqs_consumer_policy.arn
  # Assuming the EKS cluster and service account will live in the 'default' namespace initially.
  k8s_namespace            = \"default\" 
  pricing_service_sa_name  = \"pricing-service-sa\"
}

# --- 2. EKS Cluster Definition ---
# Using the community EKS module for a complete, production-ready cluster.
module \"eks\" {
  source  = \"terraform-aws-modules/eks/aws\"
  version = \"20.10.0\" # Use a stable, recent version

  cluster_name    = \"ecommerce-inventory-cluster\"
  cluster_version = \"1.29\"
  vpc_id          = local.vpc_id
  subnet_ids      = local.private_subnet_ids
  
  # Ensure the cluster creates the OIDC identity provider, required for IRSA.
  enable_cluster_creator_admin_permissions = true
  
  # We are using Fargate only, so we disable managed node groups.
  enable_managed_node_groups = false
  
  tags = {
    \"Project\" = \"CloudNative-Ecomm\"
    \"Name\"    = \"EKS-Cluster\"
  }
}

# --- 3. EKS Fargate Profile Definition (Serverless Compute) ---
# This profile tells EKS to run ALL Pods in the 'default' namespace on Fargate.
resource \"aws_eks_fargate_profile\" \"default_profile\" {
  cluster_name           = module.eks.cluster_name
  fargate_profile_name   = \"default-profile\"
  subnet_ids             = local.private_subnet_ids
  pod_execution_role_arn = module.eks.fargate_iam_role_arn # Role created by the EKS module

  selector {
    namespace = local.k8s_namespace
  }
  
  # DAY 6 COST OPTIMIZATION: Use FARGATE_SPOT capacity provider for cost savings (~70% off)
  capacity_provider = \"FARGATE_SPOT\"
}

# --- 4. IRSA for Pricing Service (SQS Consumer) ---

# 4a. IAM Trust Policy for Kubernetes Service Account (IRSA)
# This policy grants the EKS Service Account (SA) permission to assume this IAM role.
data \"aws_iam_policy_document\" \"pricing_sa_assume_role_policy\" {
  statement {
    effect = \"Allow\"
    actions = [\"sts:AssumeRoleWithWebIdentity\"]
    principals {
      type        = \"Federated\"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = \"StringEquals\"
      # The SA name must match the name used in the K8s manifest (Day 4)
      variable = \"${module.eks.oidc_provider_extract_from_arn}:sub\"
      values   = [\"system:serviceaccount:${local.k8s_namespace}:${local.pricing_service_sa_name}\"]
    }
  }
}

# 4b. IAM Role for Pricing Service
resource \"aws_iam_role\" \"pricing_service_sa_role\" {
  name               = \"EKS-PricingService-SQSConsumer\"
  assume_role_policy = data.aws_iam_policy_document.pricing_sa_assume_role_policy.json
}

# 4c. Attach the SQS Consumer Policy (from main.tf) to the Pricing Service Role
resource \"aws_iam_role_policy_attachment\" \"pricing_service_sqs_policy_attach\" {
  policy_arn = local.sqs_consumer_policy_arn
  role       = aws_iam_role.pricing_service_sa_role.name
}

# --- 5. Outputs for Day 4 (Kubernetes Manifests) ---
output \"cluster_endpoint\" {
  description = \"The endpoint for the EKS cluster.\"
  value       = module.eks.cluster_endpoint
}

output \"kubeconfig_command\" {
  description = \"Command to update local kubeconfig.\"
  value       = \"aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${module.eks.cluster_endpoint_private_access == true ? module.eks.cluster_region : var.aws_region}\"
}

output \"pricing_sa_role_arn\" {
  description = \"The ARN of the IAM Role for the Pricing Service Kubernetes Service Account.\"
  value       = aws_iam_role.pricing_service_sa_role.arn
}