resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-database"
  subnet_ids = values(aws_subnet.database)[*].id

  tags = {
    Name = "${local.name}-database"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = "${local.name}-postgres"

  engine         = "postgres"
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage_gib
  max_allocated_storage = var.db_max_allocated_storage_gib
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name                     = "voting"
  username                    = "voteapp"
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = true

  backup_retention_period   = var.db_backup_retention_days
  copy_tags_to_snapshot     = true
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-postgres-final"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  performance_insights_enabled    = true

  tags = {
    Name = "${local.name}-postgres"
  }
}
