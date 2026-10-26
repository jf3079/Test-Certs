locals {
  aws_certs_cc = merge(
    local.aws_kubra_certs_cc,
    local.aws_client_certs_cc,
  )
}

output "aws_certs_cc" {
  value = local.aws_certs_cc
}

output "source_certificates_map_cc" {
  value = local.source_certificates_map_cc
}