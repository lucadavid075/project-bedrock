variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "project-bedrock-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS (>= 1.34)"
  type        = string
  default     = "1.34"
}

variable "vpc_cidr" {
  description = "CIDR block for the project VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "student_id" {
  description = "AltSchool student ID"
  type        = string
  default     = "alt-soe-025-4887"
}

variable "state_bucket" {
  description = "S3 bucket that holds Terraform remote state"
  type        = string
  default     = "project-bedrock-tfstate-alt-soe-025-4887"
}

variable "github_repo" {
  description = "GitHub repo in owner/repo format for OIDC trust (e.g. username/project-bedrock)"
  type        = string
  default     = "lucadavid075/project-bedrock"
}

variable "cluster_admin_principal_arn" {
  description = "Stable IAM principal that should retain EKS cluster admin access"
  type        = string
  default     = "arn:aws:iam::757559216958:user/bedrock-admin"
}

variable "app_namespace" {
  description = "Kubernetes namespace for the retail application"
  type        = string
  default     = "retail-app"
}

variable "db_instance_class" {
  description = "RDS instance size — t3.micro keeps costs minimal"
  type        = string
  default     = "db.t3.micro"
}

variable "retail_store_host" {
  description = "Optional DNS hostname for the retail store Ingress, used for the HTTPS bonus path"
  type        = string
  default     = ""
}

variable "alb_certificate_arn" {
  description = "Optional ACM certificate ARN for HTTPS termination on the ALB"
  type        = string
  default     = ""
}
