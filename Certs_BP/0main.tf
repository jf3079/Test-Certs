locals {
  source_certificates_map = merge(
    local.Export_Certs_CAN-Prod,
    local.Export_Certs_CAN-UAT,
    local.Export_Certs_US-Prod,
    local.Export_Certs_US-UAT,
  )
}

output "source_certificates_map" {
  value = local.source_certificates_map
}

locals {
  aws_certs = merge(
    local.aws_kubra_certs_bp,
    local.aws_client_certs_bp,
  )
}

output "aws_certs" {
  value = local.aws_certs
}

output "additional_sans" {
  value = local.additional_sans
}