output "state_bucket_name" {
  description = "Bucket S3 do estado remoto."
  value       = aws_s3_bucket.state.id
}

output "backend_config" {
  description = "Conteúdo de terraform/backend.hcl (key fica em environments/dev/backend.tf)."
  value       = <<-EOT
    bucket = "${aws_s3_bucket.state.id}"
    region = "${var.aws_region}"
  EOT
}
