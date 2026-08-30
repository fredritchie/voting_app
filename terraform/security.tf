resource "aws_security_group" "rds" {
  name        = "${local.name}-rds"
  description = "Permit PostgreSQL only from the EKS private-node subnets"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "PostgreSQL from EKS workloads"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [for subnet in aws_subnet.private : subnet.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-rds"
  }
}
