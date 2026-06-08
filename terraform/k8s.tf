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

  # Keys match exactly what the catalog chart's deployment.yaml reads
  # via secretRef: RETAIL_CATALOG_PERSISTENCE_USER and _PASSWORD
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

  # Keys match exactly what the orders chart's deployment.yaml reads
  # via secretRef: RETAIL_ORDERS_PERSISTENCE_USERNAME and _PASSWORD
  data = {
    RETAIL_ORDERS_PERSISTENCE_USERNAME = aws_db_instance.orders.username
    RETAIL_ORDERS_PERSISTENCE_PASSWORD = random_password.orders_db.result
  }

  type = "Opaque"
}

resource "helm_release" "retail_store" {
  name      = "retail-store"
  chart     = "${path.module}/../helm/retail-store"
  namespace = kubernetes_namespace_v1.retail_app.metadata[0].name

  values = [file("${path.module}/../helm/retail-store/values.yaml")]

  # Layer 2: inject live infrastructure values
  # Endpoints, table names, IRSA ARN — not secrets, safe as set blocks
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
