resource "aws_db_subnet_group" "this" {
  name       = "rds-subnet-group-${var.environment}"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name        = "rds-subnet-group-${var.environment}"
    Environment = var.environment
  })
}

resource "aws_db_parameter_group" "this" {
  name   = "rds-pg-${var.environment}"
  family = "${var.engine}${var.engine_version}"

  tags = merge(var.tags, {
    Name        = "rds-pg-${var.environment}"
    Environment = var.environment
  })
}

resource "aws_db_instance" "this" {
  identifier = "rds-${var.environment}"

  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids
  parameter_group_name   = aws_db_parameter_group.this.name

  multi_az               = var.multi_az
  backup_retention_period = var.multi_az ? 30 : 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"

  skip_final_snapshot = var.environment == "dev" ? true : false
  final_snapshot_identifier = "rds-${var.environment}-final"

  deletion_protection = var.environment == "prod" ? true : false

  tags = merge(var.tags, {
    Name        = "rds-${var.environment}"
    Environment = var.environment
  })
}
