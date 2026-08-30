resource "aws_ecr_repository" "application" {
  for_each = toset(["vote", "result", "worker"])

  name                 = "${var.project}/${each.value}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
