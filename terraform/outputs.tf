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

output "bedrock_dev_access_key_id" {
  description = "Access Key ID for bedrock-dev-view — paste into submission doc"
  value       = aws_iam_access_key.bedrock_dev.id
  sensitive   = true
}

output "bedrock_dev_secret_access_key" {
  description = "Secret Access Key for bedrock-dev-view — paste into submission doc"
  value       = aws_iam_access_key.bedrock_dev.secret
  sensitive   = true
}

output "bedrock_dev_console_password" {
  description = "Console login password for bedrock-dev-view — paste into submission doc"
  value       = aws_iam_user_login_profile.bedrock_dev.password
  sensitive   = true
}

output "github_actions_role_arn" {
  description = "Paste this into GitHub → Settings → Secrets → AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}

output "helm_values_rds" {
  description = <<-EOT
    Generate values-rds.yaml on any machine:
      terraform output -raw helm_values_rds > ../helm/retail-store/values-rds.yaml
    Then deploy:
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
