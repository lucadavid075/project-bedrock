resource "kubernetes_namespace_v1" "retail_app" {
  metadata {
    name = var.app_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
  depends_on = [module.eks]
}

resource "helm_release" "aws_lbc" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.1"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.lbc_irsa.iam_role_arn
  }
  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  wait          = true
  wait_for_jobs = true
  timeout       = 300

  depends_on = [module.eks]
}

resource "aws_eks_access_entry" "bedrock_dev" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_user.bedrock_dev.arn
  type          = "STANDARD"
  tags          = local.tags
}

resource "aws_eks_access_policy_association" "bedrock_dev_view" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_user.bedrock_dev.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.bedrock_dev]
}

resource "kubernetes_cluster_role_binding_v1" "bedrock_dev_view" {
  metadata {
    name = "bedrock-dev-view-binding"
    labels = {
      Project = "karatu-2025-capstone"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "view"
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "User"
    name      = aws_iam_user.bedrock_dev.arn
  }

  depends_on = [aws_eks_access_policy_association.bedrock_dev_view]
}

resource "aws_eks_access_entry" "cluster_admin" {
  cluster_name  = var.cluster_name
  principal_arn = var.cluster_admin_principal_arn
  type          = "STANDARD"
  tags          = local.tags

  depends_on = [module.eks]
}

resource "aws_eks_access_policy_association" "cluster_admin" {
  cluster_name  = var.cluster_name
  principal_arn = var.cluster_admin_principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.cluster_admin]
}

resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.github_actions.arn
  type          = "STANDARD"
  tags          = local.tags

  depends_on = [module.eks]
}

resource "aws_eks_access_policy_association" "github_actions_admin" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.github_actions.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.github_actions]
}

resource "kubernetes_secret_v1" "catalog_db" {
  metadata {
    name      = "catalog-db"
    namespace = kubernetes_namespace_v1.retail_app.metadata[0].name
    labels    = { "app.kubernetes.io/managed-by" = "terraform" }
  }

  data = {
    RETAIL_CATALOG_PERSISTENCE_USER     = aws_db_instance.catalog.username
    RETAIL_CATALOG_PERSISTENCE_PASSWORD = random_password.catalog_db.result
  }

  type = "Opaque"
}

resource "kubernetes_secret_v1" "orders_db" {
  metadata {
    name      = "orders-db"
    namespace = kubernetes_namespace_v1.retail_app.metadata[0].name
    labels    = { "app.kubernetes.io/managed-by" = "terraform" }
  }

  data = {
    RETAIL_ORDERS_PERSISTENCE_USERNAME = aws_db_instance.orders.username
    RETAIL_ORDERS_PERSISTENCE_PASSWORD = random_password.orders_db.result
  }

  type = "Opaque"
}

locals {
  # Base ingress annotations always present
  base_ingress_annotations = {
    "kubernetes.io/ingress.class"                        = "alb"
    "alb.ingress.kubernetes.io/scheme"                   = "internet-facing"
    "alb.ingress.kubernetes.io/target-type"              = "ip"
    "alb.ingress.kubernetes.io/load-balancer-attributes" = "idle_timeout.timeout_seconds=60"
  }

  # TLS annotations added only when a certificate ARN is provided
  tls_ingress_annotations = var.alb_certificate_arn != "" ? {
    "alb.ingress.kubernetes.io/certificate-arn" = var.alb_certificate_arn
    "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTP\":80},{\"HTTPS\":443}]"
    "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
  } : {}

  # Merged annotations passed to the Helm chart
  ui_ingress_annotations = merge(local.base_ingress_annotations, local.tls_ingress_annotations)

  # Hosts list - empty for plain HTTP, set to domain when TLS is enabled
  ui_ingress_hosts = var.retail_store_host != "" ? [var.retail_store_host] : []
}

resource "helm_release" "retail_store" {
  name      = "retail-store"
  chart     = "${path.module}/../helm/retail-store"
  namespace = kubernetes_namespace_v1.retail_app.metadata[0].name

  atomic          = true
  wait            = true
  timeout         = 600
  cleanup_on_fail = true

  # Layer 1: base chart defaults
  # Layer 2: TLS ingress values merged in via yamlencode - avoids
  #          Terraform set block limitations with JSON annotation values
  #          such as alb.ingress.kubernetes.io/listen-ports
  values = [
    file("${path.module}/../helm/retail-store/values.yaml"),
    yamlencode({
      ui = {
        ingress = {
          enabled     = true
          className   = "alb"
          annotations = local.ui_ingress_annotations
          hosts       = local.ui_ingress_hosts
        }
      }
    })
  ]

  # Layer 3: live infrastructure values injected at apply time
  set {
    name  = "catalog.app.persistence.endpoint"
    value = aws_db_instance.catalog.endpoint
  }
  set {
    name  = "cart.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.carts_irsa.iam_role_arn
  }
  set {
    name  = "cart.app.persistence.dynamodb.tableName"
    value = aws_dynamodb_table.carts.name
  }
  set {
    name  = "orders.app.persistence.endpoint"
    value = "${aws_db_instance.orders.address}:${aws_db_instance.orders.port}"
  }

  depends_on = [
    helm_release.aws_lbc,
    kubernetes_secret_v1.catalog_db,
    kubernetes_secret_v1.orders_db,
    aws_db_instance.catalog,
    aws_db_instance.orders,
    aws_dynamodb_table.carts,
  ]
}
