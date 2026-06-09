locals {
  tags = {
    Project = "karatu-2025-capstone"
  }

  assets_bucket_name = "bedrock-assets-${var.student_id}"

  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.10.0/24", "10.0.11.0/24"]
  azs             = ["${var.region}a", "${var.region}b"]

  oidc_issuer = trimprefix(module.eks.cluster_oidc_issuer_url, "https://")

  ui_ingress_annotations = merge(
    {
      "kubernetes.io/ingress.class"                        = "alb"
      "alb.ingress.kubernetes.io/scheme"                   = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"              = "ip"
      "alb.ingress.kubernetes.io/load-balancer-attributes" = "idle_timeout.timeout_seconds=60"
    },
    var.alb_certificate_arn == "" ? {} : {
      "alb.ingress.kubernetes.io/certificate-arn" = var.alb_certificate_arn
      "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTP\":80},{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
    }
  )

  ui_ingress_hosts = var.retail_store_host == "" ? [] : [var.retail_store_host]
}
