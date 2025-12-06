locals {
  aws_region                      = var.aws_region
  java_ecr_repo_uri               = aws_ecr_repository.java_inventory_service_repo.repository_url
  pricing_ecr_repo_uri            = aws_ecr_repository.pricing_service_repo.repository_url

  eks_cluster_name                = module.eks.cluster_name
  eks_cluster_arn                 = module.eks.cluster_arn

  github_owner                    = "aslinger"
  repo_name                       = "ecommerce"
  connection_arn                  = "arn:aws:codepipeline:us-east-1:497588665354:ecomm" # AWS CodeStar Connection ARN
  branch                          = "main"
}

resource "aws_s3_bucket" "codepipeline_artifacts" {
  bucket = "${local.eks_cluster_name}-pipeline-artifacts-9485" # Unique bucket name
  force_destroy = true # Allows deletion of bucket content on terraform destroy
}

resource "aws_iam_role" "codebuild_role" {
  name = "CodeBuild-Role-Ecomm"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_role_policy" "codebuild_policy" {
  role = aws_iam_role.codebuild_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:log-group:/aws/codebuild/${aws_codebuild_project.build_project.name}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketAcl",
          "s3:GetBucketLocation",
        ]
        Resource = ["${aws_s3_bucket.codepipeline_artifacts.arn}/*", aws_s3_bucket.codepipeline_artifacts.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
        ]
        Resource = [
          aws_ecr_repository.java_inventory_service_repo.arn,
          aws_ecr_repository.pricing_service_repo.arn,
          "*"
        ]
      },
    ]
  })
}

resource "aws_iam_role" "codepipeline_role" {
  name = "CodePipeline-Role-Ecomm"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  role = aws_iam_role.codepipeline_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObjectAcl",
          "s3:PutObject"
        ]
        Resource = ["${aws_s3_bucket.codepipeline_artifacts.arn}/*", aws_s3_bucket.codepipeline_artifacts.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild",
          "codebuild:StopBuild",
          "codebuild:BatchGetBuilds"
        ]
        Resource = aws_codebuild_project.build_project.arn
      },
      {
        Effect = "Allow"
        Action = [
          "codestar-connections:UseConnection"
        ]
        Resource = local.connection_arn
      },
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster"
        ]
        Resource = local.eks_cluster_arn
      },
      # K8s Service Role for EKS Action
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = module.eks.cluster_iam_role_arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "eks.amazonaws.com"
          }
        }
      },
    ]
  })
}

resource "aws_codebuild_project" "build_project" {
  name           = "Ecomm-Container-Build"
  description    = "Builds and pushes Java and Python images to ECR."
  service_role   = aws_iam_role.codebuild_role.arn
  build_timeout  = "60"

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type                        = "LINUX_CONTAINER"
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }
    environment_variable {
      name  = "JAVA_REPO_URI"
      value = local.java_ecr_repo_uri
    }
    environment_variable {
      name  = "PYTHON_REPO_URI"
      value = local.pricing_ecr_repo_uri
    }
    environment_variable {
      name  = "AWS_REGION"
      value = local.aws_region
    }
  }

  source {
    type            = "CODEPIPELINE"
    buildspec       = file("buildspec.yml")
  }
}

data "aws_caller_identity" "current" {}

resource "aws_sns_topic" "approval_topic" {
  name = "EKS-Canary-Approval-Required"
}

resource "aws_codebuild_project" "deploy_to_eks_project" {
  name          = "Ecomm-EKS-Deploy-Project"
  service_role  = aws_iam_role.codebuild_role.arn
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    type            = "LINUX_CONTAINER"
    image           = "aws/codebuild/standard:5.0"
    compute_type    = "BUILD_GENERAL1_SMALL"
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = file("buildspec.yml")
  }
}


resource "aws_codepipeline" "main_pipeline" {
  name     = "Ecomm-EKS-CI-CD-Pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_artifacts.bucket
    type     = "S3"
  }

  # --- Stage 1: Source ---
  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_artifact"]

      configuration = {
        ConnectionArn    = local.connection_arn
        FullRepositoryId = "${local.github_owner}/${local.repo_name}"
        BranchName       = local.branch
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "BuildAndPush"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_artifact"]
      output_artifacts = ["build_artifact"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.build_project.name
      }
    }
  }

  stage {
    name = "Deploy_Canary"
    action {
      name            = "Deploy_Pricing_Canary"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "Ecs"
      input_artifacts = ["build_output"]
      version         = "1"
      run_order       = 1
      configuration = {
        ClusterName    = local.eks_cluster_name
        FileName       = "imagedefinitions.json"
        DeploymentFile = "k8s/pricing-deployment-canary.yaml,k8s/configmap.yaml"
      }
    }
  }

  stage {
    name = "Approve_Canary"
    action {
      name     = "Manual_Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"
      configuration = {
        NotificationArn = aws_sns_topic.approval_topic.arn
        CustomData      = "Approve the canary deployment to roll out to full production."
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name             = "DeployToEKS"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["build_artifact"]
      output_artifacts = []

      configuration = {
        ProjectName = aws_codebuild_project.deploy_to_eks_project.name
      }
    }
  }
}