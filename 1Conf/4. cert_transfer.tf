locals {
  source_config = {
    region      = "us-east-1"
    secret_name = "acm/export_passphrase"
  }
}

resource "null_resource" "install_dependencies" {
  triggers = {
    run_on_every_apply = timestamp()
  }
  provisioner "local-exec" {
    command = "pip3 install boto3 cryptography --user --quiet"
  }
}

resource "aws_secretsmanager_secret" "acm_export_passphrase" {
  name        = "acm/export_passphrase"
  description = "Passphrase used to export ACM certificate private keys"
}

resource "aws_secretsmanager_secret_version" "acm_export_passphrase_version" {
  secret_id     = aws_secretsmanager_secret.acm_export_passphrase.id
  secret_string = var.acm_export_passphrase
}

#-----------------------------------BP------------------------------------------#
locals {
  source_certificates_map = module.Certs.source_certificates_map
}

locals {
  transfer_matrix = {
    for pair in flatten([
      for account_id, cfg in local.source_certificates_map : [
        for region in cfg.regions : [
          for certs in cfg.certs : {
            account_id = account_id
            region     = region
            certs      = certs
          }
        ]
      ]
    ]) : "${pair.account_id}-${pair.region}-${pair.certs}" => pair
  }
}

resource "local_file" "python_configs" {
  for_each = local.transfer_matrix

  content = jsonencode({
    cert_arn        = try(aws_acm_certificate.aws-cert[each.value.certs].arn, each.value.certs)
    source_region   = local.source_config.region
    dest_account_id = each.value.account_id
    dest_region     = each.value.region
    role_name       = var.role_name
    secret_name     = local.source_config.secret_name
  })

  filename = "${path.module}/config-${each.key}.json"
}

resource "null_resource" "run_transfer_script" {
  for_each = local.transfer_matrix

  triggers = {
    always_run = timestamp()
    cert_arn   = try(aws_acm_certificate.aws-cert[each.value.certs].arn, each.value.certs)
  }

  depends_on = [
    local_file.python_configs,
    null_resource.install_dependencies
  ]

  provisioner "local-exec" {
    command = "python3 ${path.module}/transfer_cert.py ${path.module}/config-${each.key}.json"
  }
}

#-----------------------------------CC------------------------------------------#
locals {
  source_certificates_map_cc = module.Certs_CC.source_certificates_map_cc
}

locals {
  transfer_matrix_cc = {
    for pair in flatten([
      for group_key, cfg in local.source_certificates_map_cc : [
        for account_id in cfg.account_ids : [
          for region in cfg.regions : [
            for certs in cfg.certs : {
              account_id = account_id
              region     = region
              certs      = certs
            }
          ]
        ]
      ]
    ]) : "${pair.account_id}-${pair.region}-${pair.certs}" => pair
  }
}

resource "local_file" "python_configs_cc" {
  for_each = local.transfer_matrix_cc

  content = jsonencode({
    cert_arn        = try(aws_acm_certificate.aws-cert-cc[each.value.certs].arn, each.value.certs)
    source_region   = local.source_config.region
    dest_account_id = each.value.account_id
    dest_region     = each.value.region
    role_name       = var.role_name
    secret_name     = local.source_config.secret_name
  })

  filename = "${path.module}/config-${each.key}.json"
}

resource "null_resource" "run_transfer_script_cc" {
  for_each = local.transfer_matrix_cc

  triggers = {
    always_run = timestamp()
    cert_arn   = try(aws_acm_certificate.aws-cert-cc[each.value.certs].arn, each.value.certs)
  }

  depends_on = [
    local_file.python_configs,
    null_resource.install_dependencies
  ]

  provisioner "local-exec" {
    command = "python3 ${path.module}/transfer_cert.py ${path.module}/config-${each.key}.json"
  }
}