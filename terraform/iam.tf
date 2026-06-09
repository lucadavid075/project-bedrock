resource "aws_iam_user" "bedrock_dev" {
  name = "bedrock-dev-view"
  tags = local.tags
}

resource "aws_iam_user_login_profile" "bedrock_dev" {
  user                    = aws_iam_user.bedrock_dev.name
  password_reset_required = false
}

resource "aws_iam_access_key" "bedrock_dev" {
  user = aws_iam_user.bedrock_dev.name
}

# AWS Console: ReadOnlyAccess
resource "aws_iam_user_policy_attachment" "bedrock_dev_readonly" {
  user       = aws_iam_user.bedrock_dev.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# S3: PutObject on the assets bucket
resource "aws_iam_policy" "bedrock_dev_s3" {
  name        = "bedrock-dev-s3-putobject"
  description = "Allow bedrock-dev-view to upload objects to the assets bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.assets.arn}/*"
    }]
  })

  tags = local.tags
}

resource "aws_iam_user_policy_attachment" "bedrock_dev_s3" {
  user       = aws_iam_user.bedrock_dev.name
  policy_arn = aws_iam_policy.bedrock_dev_s3.arn
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_actions" {
  name = "${var.cluster_name}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
        }
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = local.tags
}

# Policy 1 of 2 — Compute, networking and storage
resource "aws_iam_policy" "github_actions_cicd_1" {
  name        = "${var.cluster_name}-cicd-compute"
  description = "CI/CD policy part 1: EKS, EC2, RDS, DynamoDB, S3, Lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKS"
        Effect = "Allow"
        Action = [
          "eks:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2"
        Effect = "Allow"
        Action = [
          "ec2:Describe*", "ec2:List*", "ec2:Get*",
          "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
          "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
          "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway",
          "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
          "ec2:CreateNatGateway", "ec2:DeleteNatGateway",
          "ec2:AllocateAddress", "ec2:ReleaseAddress",
          "ec2:CreateRouteTable", "ec2:DeleteRouteTable",
          "ec2:CreateRoute", "ec2:DeleteRoute",
          "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
          "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
          "ec2:CreateTags", "ec2:DeleteTags",
          "ec2:RunInstances", "ec2:TerminateInstances",
          "ec2:CreateLaunchTemplate", "ec2:DeleteLaunchTemplate",
          "ec2:CreateLaunchTemplateVersion", "ec2:ModifyLaunchTemplate",
          "ec2:CreateNetworkAcl", "ec2:DeleteNetworkAcl",
          "ec2:CreateNetworkAclEntry", "ec2:DeleteNetworkAclEntry",
          "ec2:ReplaceNetworkAclAssociation", "ec2:ReplaceNetworkAclEntry",
          "ec2:ModifyVpcEndpoint", "ec2:CreateVpcEndpoint", "ec2:DeleteVpcEndpoints",
          "ec2:AssociateVpcCidrBlock", "ec2:DisassociateVpcCidrBlock",
          "ec2:ModifySubnetAttribute"
        ]
        Resource = "*"
      },
      {
        Sid      = "AutoScaling"
        Effect   = "Allow"
        Action   = ["autoscaling:*"]
        Resource = "*"
      },
      {
        Sid    = "RDS"
        Effect = "Allow"
        Action = [
          "rds:CreateDBInstance", "rds:DeleteDBInstance", "rds:ModifyDBInstance",
          "rds:DescribeDBInstances", "rds:CreateDBSubnetGroup",
          "rds:DeleteDBSubnetGroup", "rds:DescribeDBSubnetGroups",
          "rds:AddTagsToResource", "rds:ListTagsForResource",
          "rds:DescribeDBEngineVersions", "rds:DescribeOrderableDBInstanceOptions"
        ]
        Resource = "*"
      },
      {
        Sid    = "DynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:CreateTable", "dynamodb:DeleteTable",
          "dynamodb:DescribeTable", "dynamodb:UpdateTable",
          "dynamodb:ListTables", "dynamodb:TagResource",
          "dynamodb:UntagResource", "dynamodb:ListTagsOfResource",
          "dynamodb:DescribeContinuousBackups",
          "dynamodb:DescribeTimeToLive"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket", "s3:DeleteBucket", "s3:ListBucket",
          "s3:GetBucketLocation", "s3:GetBucketVersioning", "s3:PutBucketVersioning",
          "s3:GetBucketPublicAccessBlock", "s3:PutBucketPublicAccessBlock",
          "s3:GetEncryptionConfiguration", "s3:PutEncryptionConfiguration",
          "s3:GetBucketNotification", "s3:PutBucketNotification",
          "s3:GetBucketPolicy", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy",
          "s3:GetBucketTagging", "s3:PutBucketTagging",
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
          "s3:ListBucketVersions", "s3:GetBucketAcl", "s3:PutBucketAcl",
          "s3:GetBucketObjectLockConfiguration",
          "s3:GetBucketRequestPayment",
          "s3:GetBucketWebsite",
          "s3:GetBucketCORS",
          "s3:GetAccelerateConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:GetReplicationConfiguration",
          "s3:GetBucketLogging",
          "s3:PutBucketLogging"
        ]
        Resource = "*"
      },
      {
        Sid    = "Lambda"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction", "lambda:DeleteFunction", "lambda:GetFunction",
          "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration",
          "lambda:AddPermission", "lambda:RemovePermission", "lambda:GetPolicy",
          "lambda:ListFunctions", "lambda:TagResource", "lambda:InvokeFunction",
          "lambda:ListVersionsByFunction", "lambda:GetFunctionCodeSigningConfig",
          "lambda:PutFunctionEventInvokeConfig", "lambda:GetFunctionEventInvokeConfig",
          "lambda:ListAliases"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.tags
}

# Policy 2 of 2 — IAM, observability and supporting services
resource "aws_iam_policy" "github_actions_cicd_2" {
  name        = "${var.cluster_name}-cicd-iam-obs"
  description = "CI/CD policy part 2: IAM, Secrets Manager, CloudWatch, ELB, KMS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "IAM"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole",
          "iam:UpdateAssumeRolePolicy", "iam:PassRole",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy",
		  "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
          "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy",
          "iam:GetPolicyVersion", "iam:ListPolicyVersions",
          "iam:ListAttachedRolePolicies", "iam:ListRolePolicies",
          "iam:GetRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
          "iam:TagRole", "iam:UntagRole", "iam:TagPolicy", "iam:UntagPolicy",
          "iam:CreateUser", "iam:DeleteUser", "iam:GetUser", "iam:TagUser",
          "iam:CreateAccessKey", "iam:DeleteAccessKey", "iam:ListAccessKeys",
          "iam:AttachUserPolicy", "iam:DetachUserPolicy",
          "iam:ListAttachedUserPolicies",
          "iam:CreateLoginProfile", "iam:DeleteLoginProfile", "iam:GetLoginProfile",
          "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider", "iam:ListOpenIDConnectProviders",
          "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile", "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile", "iam:ListInstanceProfilesForRole",
          "iam:ListRoles"
        ]
        Resource = "*"
      },
      {
        Sid    = "SecretsManager"
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret", "secretsmanager:DeleteSecret",
          "secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue",
          "secretsmanager:DescribeSecret", "secretsmanager:ListSecrets",
          "secretsmanager:TagResource", "secretsmanager:UpdateSecret",
          "secretsmanager:GetResourcePolicy", "secretsmanager:PutResourcePolicy",
          "secretsmanager:DeleteResourcePolicy"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatch"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:DescribeLogGroups",
          "logs:CreateLogStream", "logs:PutLogEvents", "logs:GetLogEvents",
          "logs:PutRetentionPolicy", "logs:TagResource", "logs:UntagResource",
          "logs:ListTagsForResource", "logs:ListTagsLogGroup",
          "logs:DescribeLogStreams", "logs:DeleteLogStream",
          "cloudwatch:PutMetricData", "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics", "cloudwatch:DescribeAlarms"
        ]
        Resource = "*"
      },
      {
        Sid      = "ELB"
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:*"]
        Resource = "*"
      },
      {
        Sid    = "ACM"
        Effect = "Allow"
        Action = [
          "acm:AddTagsToCertificate",
          "acm:DescribeCertificate",
          "acm:GetCertificate",
          "acm:ImportCertificate",
          "acm:ListCertificates",
          "acm:ListTagsForCertificate"
        ]
        Resource = "*"
      },
      {
        Sid    = "KMS"
        Effect = "Allow"
        Action = [
          "kms:CreateKey", "kms:DescribeKey", "kms:ListKeys",
          "kms:ListAliases", "kms:CreateAlias", "kms:DeleteAlias",
          "kms:GenerateDataKey", "kms:Decrypt", "kms:Encrypt",
          "kms:TagResource", "kms:UntagResource",
          "kms:GetKeyPolicy", "kms:PutKeyPolicy",
          "kms:GetKeyRotationStatus", "kms:EnableKeyRotation",
          "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion",
          "kms:ListResourceTags", "kms:ListGrants",
          "kms:CreateGrant", "kms:RevokeGrant"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "github_actions_cicd_1" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_cicd_1.arn
}

resource "aws_iam_role_policy_attachment" "github_actions_cicd_2" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_cicd_2.arn
}

resource "aws_iam_policy" "carts_dynamodb" {
  name        = "${var.cluster_name}-carts-dynamodb"
  description = "Allow carts service to perform item-level operations on its own table only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CartItemOperations"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:DescribeTable"
        ]
        Resource = [
          aws_dynamodb_table.carts.arn,
          "${aws_dynamodb_table.carts.arn}/index/*"
        ]
      }
    ]
  })

  tags = local.tags
}

module "carts_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-carts"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.app_namespace}:carts"]
    }
  }

  role_policy_arns = {
    dynamodb = aws_iam_policy.carts_dynamodb.arn
  }

  tags = local.tags
}

module "lbc_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${var.cluster_name}-aws-lbc"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.tags
}
