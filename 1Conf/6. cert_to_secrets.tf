variable "secret_prefix" {
  type    = string
  default = "acm-export"
}

#-----------------------------------BP------------------------------------------#
# Reuses local.transfer_matrix (account_id / region / cert) from 4. cert_transfer.tf
resource "local_file" "secret_configs" {
  for_each = local.transfer_matrix

  content = jsonencode({
    cert_arn        = try(aws_acm_certificate.aws-cert[each.value.certs].arn, each.value.certs)
    source_region   = local.source_config.region
    dest_account_id = each.value.account_id
    dest_region     = each.value.region
    role_name       = var.role_name
    secret_name     = local.source_config.secret_name
    secret_prefix   = var.secret_prefix
  })

  filename = "${path.module}/secret-config-${each.key}.json"
}

resource "null_resource" "export_to_secrets" {
  for_each = local.transfer_matrix

  triggers = {
    always_run = timestamp()
    cert_arn   = try(aws_acm_certificate.aws-cert[each.value.certs].arn, each.value.certs)
  }

  depends_on = [
    local_file.secret_configs,
    null_resource.install_dependencies
  ]

  provisioner "local-exec" {
    command = "python3 ${path.module}/export_cert_to_secret.py ${path.module}/secret-config-${each.key}.json"
  }
}

#-----------------------------------CC------------------------------------------#
# Reuses local.transfer_matrix_cc
resource "local_file" "secret_configs_cc" {
  for_each = local.transfer_matrix_cc

  content = jsonencode({
    cert_arn        = try(aws_acm_certificate.aws-cert-cc[each.value.certs].arn, each.value.certs)
    source_region   = local.source_config.region
    dest_account_id = each.value.account_id
    dest_region     = each.value.region
    role_name       = var.role_name
    secret_name     = local.source_config.secret_name
    secret_prefix   = var.secret_prefix
  })

  filename = "${path.module}/secret-config-${each.key}.json"
}

resource "null_resource" "export_to_secrets_cc" {
  for_each = local.transfer_matrix_cc

  triggers = {
    always_run = timestamp()
    cert_arn   = try(aws_acm_certificate.aws-cert-cc[each.value.certs].arn, each.value.certs)
  }

  depends_on = [
    local_file.secret_configs_cc,
    null_resource.install_dependencies
  ]

  provisioner "local-exec" {
    command = "python3 ${path.module}/export_cert_to_secret.py ${path.module}/secret-config-${each.key}.json"
  }
}
