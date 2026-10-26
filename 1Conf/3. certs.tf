#------------------------------------BP-----------------------------------#
locals {
  aws_certs       = module.Certs.aws_certs
  additional_sans = module.Certs.additional_sans
}

resource "aws_acm_certificate" "aws-cert" {
  for_each          = local.aws_certs
  domain_name       = each.key
  validation_method = "DNS"
  subject_alternative_names = distinct(concat(
    startswith(each.key, "*.") ? [trimprefix(each.key, "*.")] : [],
    lookup(local.additional_sans, each.key, [])
  ))

  options {
    export = "ENABLED"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    "Name"               = "BP-${startswith(each.key, "*.") ? "star.${substr(each.key, 2, length(each.key))}" : each.key}-${each.value}"
    "OD_Name"            = "BP-${startswith(each.key, "*.") ? "star.${substr(each.key, 2, length(each.key))}" : each.key}"
    "Certificate Number" = each.value
  }
}

#------------------------------------CC-----------------------------------#
locals {
  aws_certs_cc = module.Certs_CC.aws_certs_cc
}

resource "aws_acm_certificate" "aws-cert-cc" {
  for_each                  = local.aws_certs_cc
  domain_name               = each.key
  validation_method         = "DNS"
  subject_alternative_names = try(each.value.subject_alternative_names, [])

  options {
    export = "ENABLED"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    "Name"               = "CC-${startswith(each.key, "*.") ? "star.${substr(each.key, 2, length(each.key))}" : each.key}-${each.value.number}"
    "Certificate Number" = each.value.number
  }
}

#-------------------------------------------------------------------------------------------------#