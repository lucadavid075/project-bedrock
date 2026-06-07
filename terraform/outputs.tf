output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "assets_bucket_name" {
  description = "S3 assets bucket name"
  value       = aws_s3_bucket.assets.bucket
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded CA data for the EKS cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "catalog_rds_endpoint" {
  description = "MySQL RDS endpoint (catalog)"
  value       = aws_db_instance.catalog.endpoint
}

output "orders_rds_endpoint" {
  description = "PostgreSQL RDS endpoint (orders)"
  value       = aws_db_instance.orders.endpoint
}

output "carts_dynamodb_table_name" {
  description = "DynamoDB table name for carts"
  value       = aws_dynamodb_table.carts.name
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.asset_processor.function_name
}

output "bedrock_dev_access_key_id" {
  description = "Access Key ID for bedrock-dev-view (submit to grader)"
  value       = aws_iam_access_key.bedrock_dev.id
  sensitive   = true
}

output "bedrock_dev_secret_access_key" {
  description = "Secret Access Key for bedrock-dev-view (submit to grader)"
  value       = aws_iam_access_key.bedrock_dev.secret
  sensitive   = true
}

output "bedrock_dev_console_password" {
  description = "Console password for bedrock-dev-view"
  value       = aws_iam_user_login_profile.bedrock_dev.password
  sensitive   = true
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC"
  value       = aws_iam_role.github_actions.arn
}

output "helm_values_rds" {
  description = <<-EOT
    Ready-to-use Helm values for the managed data layer.
    Generate values-rds.yaml on any machine with:
      terraform output -raw helm_values_rds > ../helm/retail-store/values-rds.yaml
    Then deploy with:
      helm upgrade --install retail-store ./helm/retail-store \
        --namespace retail-app --create-namespace \
        -f helm/retail-store/values-rds.yaml
  EOT
  sensitive   = true
  value = yamlencode({
    catalog = {
      app = {
        persistence = {
          endpoint = aws_db_instance.catalog.endpoint
          database = "catalog"
          secret = {
            create = false
            name   = "catalog-db"
          }
        }
      }
    }
    cart = {
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = module.carts_irsa.iam_role_arn
        }
      }
      app = {
        persistence = {
          dynamodb = {
            tableName   = aws_dynamodb_table.carts.name
            createTable = false
          }
        }
      }
    }
    orders = {
      app = {
        persistence = {
          endpoint = "${aws_db_instance.orders.address}:${aws_db_instance.orders.port}"
          database = "orders"
          secret = {
            create = false
            name   = "orders-db"
          }
        }
      }
    }
  })
}
