locals {
  vpc_id                   = module.vpc.vpc_id
  private_subnet_ids       = module.vpc.private_subnets
  sqs_consumer_policy_arn  = aws_iam_policy.sqs_consumer_policy.arn
  k8s_namespace            = "default" 
  pricing_service_sa_name  = "pricing-service-sa"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.10.0"

  cluster_name    = "ecommerce-inventory-cluster"
  cluster_version = "1.29"
  vpc_id          = local.vpc_id
  subnet_ids      = local.private_subnet_ids

  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups    = {}
  self_managed_node_groups = {}
  
  tags = {
    "Project" = "CloudNative-Ecomm"
    "Name"    = "EKS-Cluster"
  }
}

data "aws_iam_policy_document" "fargate_assume_role" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks-fargate-pods.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "fargate_pod_execution_role" {
  name_prefix        = "eks-fargate-pod-execution"
  assume_role_policy = data.aws_iam_policy_document.fargate_assume_role.json
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution_role_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.fargate_pod_execution_role.name
}

# --- 3. EKS Fargate Profile Definition (Serverless Compute) ---
# This profile tells EKS to run ALL Pods in the 'default' namespace on Fargate.
resource "aws_eks_fargate_profile" "default_profile" {
  cluster_name           = module.eks.cluster_name
  fargate_profile_name   = "default-profile"
  subnet_ids             = local.private_subnet_ids
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution_role.arn

  selector {
    namespace = local.k8s_namespace
  }
}

data "aws_iam_policy_document" "pricing_sa_assume_role_policy" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:${local.k8s_namespace}:${local.pricing_service_sa_name}"]
    }
  }
}

resource "aws_iam_role" "pricing_service_sa_role" {
  name               = "EKS-PricingService-SQSConsumer"
  assume_role_policy = data.aws_iam_policy_document.pricing_sa_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "pricing_service_sqs_policy_attach" {
  policy_arn = local.sqs_consumer_policy_arn
  role       = aws_iam_role.pricing_service_sa_role.name
}

output "cluster_endpoint" {
  description = "The endpoint for the EKS cluster."
  value       = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  description = "Command to update local kubeconfig."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}
output "pricing_sa_role_arn" {
  description = "The ARN of the IAM Role for the Pricing Service Kubernetes Service Account."
  value       = aws_iam_role.pricing_service_sa_role.arn
}