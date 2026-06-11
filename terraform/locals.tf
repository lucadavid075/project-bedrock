locals {
  tags = {
    Project = "karatu-2025-capstone"
  }

  assets_bucket_name = "bedrock-assets-${var.student_id}"

  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.10.0/24", "10.0.11.0/24"]
  azs             = ["${var.region}a", "${var.region}b"]

  oidc_issuer = trimprefix(module.eks.cluster_oidc_issuer_url, "https://")
}