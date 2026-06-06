resource "random_password" "catalog_db" {
  length  = 16
  special = false
}

resource "random_password" "orders_db" {
  length  = 16
  special = false
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.cluster_name}-db-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = merge(local.tags, { Name = "${var.cluster_name}-db-subnet-group" })
}

resource "aws_security_group" "catalog_rds" {
  name        = "${var.cluster_name}-catalog-rds"
  vpc_id      = module.vpc.vpc_id
  description = "Allow MySQL traffic from EKS nodes"

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${var.cluster_name}-catalog-rds" })
}

resource "aws_security_group" "orders_rds" {
  name        = "${var.cluster_name}-orders-rds"
  vpc_id      = module.vpc.vpc_id
  description = "Allow PostgreSQL traffic from EKS nodes"

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${var.cluster_name}-orders-rds" })
}

resource "aws_db_instance" "catalog" {
  identifier             = "${var.cluster_name}-catalog"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  db_name                = "catalog"
  username               = "catalog_admin"
  password               = random_password.catalog_db.result
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.catalog_rds.id]
  skip_final_snapshot    = true
  storage_encrypted      = true
  publicly_accessible    = false
  multi_az               = false

  tags = merge(local.tags, { Name = "${var.cluster_name}-catalog" })
}

resource "aws_db_instance" "orders" {
  identifier             = "${var.cluster_name}-orders"
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  db_name                = "orders"
  username               = "orders_admin"
  password               = random_password.orders_db.result
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.orders_rds.id]
  skip_final_snapshot    = true
  storage_encrypted      = true
  publicly_accessible    = false
  multi_az               = false

  tags = merge(local.tags, { Name = "${var.cluster_name}-orders" })
}

resource "aws_dynamodb_table" "carts" {
  name         = "${var.cluster_name}-carts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "customerId"
    type = "S"
  }

  global_secondary_index {
    name            = "idx_global_customerId"
    hash_key        = "customerId"
    projection_type = "ALL"
  }

  tags = merge(local.tags, { Name = "${var.cluster_name}-carts" })
}

resource "aws_secretsmanager_secret" "catalog_db" {
  name                    = "${var.cluster_name}/catalog-db"
  recovery_window_in_days = 0

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "catalog_db" {
  secret_id = aws_secretsmanager_secret.catalog_db.id
  secret_string = jsonencode({
    username = aws_db_instance.catalog.username
    password = random_password.catalog_db.result
    endpoint = aws_db_instance.catalog.endpoint
    dbname   = aws_db_instance.catalog.db_name
  })
}

resource "aws_secretsmanager_secret" "orders_db" {
  name                    = "${var.cluster_name}/orders-db"
  recovery_window_in_days = 0

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "orders_db" {
  secret_id = aws_secretsmanager_secret.orders_db.id
  secret_string = jsonencode({
    username = aws_db_instance.orders.username
    password = random_password.orders_db.result
    host     = aws_db_instance.orders.address
    port     = aws_db_instance.orders.port
    dbname   = aws_db_instance.orders.db_name
  })
}
