#
# Day 5: Automated CI/CD Pipeline (CodePipeline, CodeBuild, IAM)
# This file provisions the automation layer that connects Git, builds images, and deploys to EKS.
#

# --- 1. Load Outputs from Previous Days ---
locals {
  # From Day 1 (main.tf)
  aws_region                      = var.aws_region
  java_ecr_repo_uri               = aws_ecr_repository.java_inventory_service_repo.repository_url
  pricing_ecr_repo_uri            = aws_ecr_repository.pricing_service_repo.repository_url
  
  # From Day 2 (eks_cluster.tf)
  eks_cluster_name                = module.eks.cluster_name
  # The Cluster ARN is needed for CodePipeline's EKS deployment permissions
  eks_cluster_arn                 = module.eks.cluster_arn
  
  # GitHub Source Configuration (TODO: Replace these placeholders)
  github_owner                    = \"TODO_GITHUB_OWNER\"
  repo_name                       = \"TODO_REPO_NAME\"
  connection_arn                  = \"TODO_CONNECTION_ARN\" # AWS CodeStar Connection ARN
  branch                          = \"main\"
}

# --- 2. CodePipeline Artifact Store (S3) ---
# S3 is required to temporarily store artifacts (source code, build output, K8s manifests)
resource \"aws_s3_bucket\" \"codepipeline_artifacts\" {
  bucket = \"${local.eks_cluster_name}-pipeline-artifacts-9485\" # Unique bucket name
  force_destroy = true # Allows deletion of bucket content on terraform destroy
}

resource \"aws_s3_bucket_acl\" \"codepipeline_artifacts_acl\" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id
  acl    = \"private\"
}

# --- 3. IAM Roles and Policies ---

# 3a. CodeBuild Role: Allows building and pushing to ECR
resource \"aws_iam_role\" \"codebuild_role\" {
  name = \"CodeBuild-Role-Ecomm\"
  assume_role_policy = jsonencode({
    Version = \"2012-10-17\"
    Statement = [
      {
        Effect = \"Allow\"
        Principal = {
          Service = \"codebuild.amazonaws.com\"
        }
        Action = \"sts:AssumeRole\"
      },
    ]
  })
}

resource \"aws_iam_role_policy\" \"codebuild_policy\" {
  role = aws_iam_role.codebuild_role.name

  policy = jsonencode({
    Version = \"2012-10-17\"
    Statement = [
      # CloudWatch Logs for build output
      {
        Effect = \"Allow\"
        Action = [
          \"logs:CreateLogGroup\",
          \"logs:CreateLogStream\",
          \"logs:PutLogEvents\",
        ]
        Resource = \"arn:aws:logs:*:*:log-group:/aws/codebuild/${aws_codebuild_project.build_project.name}:*\"
      },
      # S3 Access for pipeline artifacts
      {
        Effect = \"Allow\"
        Action = [
          \"s3:PutObject\",
          \"s3:GetObject\",
          \"s3:GetObjectVersion\",
          \"s3:GetBucketAcl\",
          \"s3:GetBucketLocation\",
        ]
        Resource = [\"${aws_s3_bucket.codepipeline_artifacts.arn}/*\", aws_s3_bucket.codepipeline_artifacts.arn]
      },
      # ECR Access (Get, BatchCheck, Upload, PutImage)
      {
        Effect = \"Allow\"
        Action = [
          \"ecr:GetAuthorizationToken\",
          \"ecr:BatchCheckLayerAvailability\",
          \"ecr:GetDownloadUrlForLayer\",
          \"ecr:GetRepositoryPolicy\",
          \"ecr:DescribeRepositories\",
          \"ecr:ListImages\",
          \"ecr:DescribeImages\",
          \"ecr:BatchGetImage\",
          \"ecr:InitiateLayerUpload\",
          \"ecr:UploadLayerPart\",
          \"ecr:CompleteLayerUpload\",
          \"ecr:PutImage\",
        ]
        Resource = [
          aws_ecr_repository.java_inventory_service_repo.arn,
          aws_ecr_repository.pricing_service_repo.arn,
          \"*\" # ECR token access requires this wide permission
        ]
      },
    ]
  })
}

# 3b. CodePipeline Role: Allows orchestration between stages
resource \"aws_iam_role\" \"codepipeline_role\" {
  name = \"CodePipeline-Role-Ecomm\"
  assume_role_policy = jsonencode({
    Version = \"2012-10-17\"
    Statement = [
      {
        Effect = \"Allow\"
        Principal = {
          Service = \"codepipeline.amazonaws.com\"
        }
        Action = \"sts:AssumeRole\"
      },
    ]
  })
}

resource \"aws_iam_role_policy\" \"codepipeline_policy\" {
  role = aws_iam_role.codepipeline_role.name

  policy = jsonencode({
    Version = \"2012-10-17\"
    Statement = [
      # Access to S3 artifacts
      {
        Effect = \"Allow\"
        Action = [
          \"s3:GetObject\",
          \"s3:GetObjectVersion\",
          \"s3:GetBucketVersioning\",
          \"s3:PutObjectAcl\",
          \"s3:PutObject\"
        ]
        Resource = [\"${aws_s3_bucket.codepipeline_artifacts.arn}/*\", aws_s3_bucket.codepipeline_artifacts.arn]
      },
      # Access to CodeBuild
      {
        Effect = \"Allow\"
        Action = [
          \"codebuild:StartBuild\",
          \"codebuild:StopBuild\",
          \"codebuild:BatchGetBuilds\"
        ]
        Resource = aws_codebuild_project.build_project.arn
      },
      # Access to CodeStar Connection (for GitHub source)
      {
        Effect = \"Allow\"
        Action = [
          \"codestar-connections:UseConnection\"
        ]
        Resource = local.connection_arn
      },
      # EKS Deployment Access (Crucial for the Deploy Stage)
      {
        Effect = \"Allow\"
        Action = [
          \"eks:DescribeCluster\"
        ]
        Resource = local.eks_cluster_arn
      },
      # K8s Service Role for EKS Action
      {
        Effect = \"Allow\"
        Action = [
          \"iam:PassRole\"
        ]
        Resource = module.eks.cluster_iam_role_arn
        Condition = {
          StringEquals = {
            \"iam:PassedToService\" = \"eks.amazonaws.com\"
          }
        }
      },
    ]
  })
}

# --- 4. CodeBuild Project Definition ---
resource \"aws_codebuild_project\" \"build_project\" {
  name           = \"Ecomm-Container-Build\"
  description    = \"Builds and pushes Java and Python images to ECR.\"
  service_role   = aws_iam_role.codebuild_role.arn
  build_timeout  = \"60\"

  artifacts {
    type = \"CODEPIPELINE\"
  }

  environment {
    type                        = \"LINUX_CONTAINER\"
    compute_type                = \"BUILD_GENERAL1_SMALL\"
    image                       = \"aws/codebuild/standard:7.0\"
    # IMPORTANT: These must match the placeholders in buildspec.yml (Day 4)
    environment_variable {
      name  = \"AWS_ACCOUNT_ID\"
      value = data.aws_caller_identity.current.account_id
    }
    environment_variable {
      name  = \"JAVA_REPO_URI\"
      value = local.java_ecr_repo_uri
    }
    environment_variable {
      name  = \"PYTHON_REPO_URI\"
      value = local.pricing_ecr_repo_uri
    }
    environment_variable {
      name  = \"AWS_REGION\"
      value = local.aws_region
    }
  }

  source {
    type            = \"CODEPIPELINE\"
    buildspec       = file(\"buildspec.yml\") # Reference to the Day 4 buildspec file
  }
}

data \"aws_caller_identity\" \"current\" {}

# --- 5. CodePipeline Definition (Orchestration) ---
resource \"aws_codepipeline\" \"main_pipeline\" {
  name     = \"Ecomm-EKS-CI-CD-Pipeline\"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_artifacts.bucket
    type     = \"S3\"
  }

  # --- Stage 1: Source ---
  stage {
    name = \"Source\"
    action {
      name             = \"Source\"
      category         = \"Source\"
      owner            = \"AWS\"
      provider         = \"CodeStarSourceConnection\"
      version          = \"1\"
      output_artifacts = [\"source_output\"]

      configuration = {
        ConnectionArn    = local.connection_arn
        FullRepositoryId = \"${local.github_owner}/${local.repo_name}\"
        BranchName       = local.branch
      }
    }
  }

  # --- Stage 2: Build and Push Images ---
  stage {
    name = \"Build\"
    action {
      name             = \"BuildAndPush\"
      category         = \"Build\"
      owner            = \"AWS\"
      provider         = \"CodeBuild\"
      input_artifacts  = [\"source_output\"]
      output_artifacts = [\"build_output\"] # Contains imagedefinitions.json and K8s YAML
      version          = \"1\"

      configuration = {
        ProjectName = aws_codebuild_project.build_project.name
      }
    }
  }

  # --- Stage 3: Deploy to EKS ---
  stage {
    name = \"Deploy\"
    action {
      name            = \"DeployToEKS\"
      category        = \"Deploy\"
      owner           = \"AWS\"
      provider        = \"Ecs\" # Use ECS provider for EKS deployment action type
      input_artifacts = [\"build_output\"] 
      version         = \"1\"

      configuration = {
        ClusterName    = local.eks_cluster_name
        FileName       = \"imagedefinitions.json\" # File created by buildspec.yml (Day 4)
        DeploymentFile = \"k8s/java-inventory-deployment.yaml,k8s/pricing-deployment.yaml,k8s/configmap.yaml\"
      }
    }
  }
}