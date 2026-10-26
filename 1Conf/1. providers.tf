terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
  cloud {
    organization = "KubOrg1"
    workspaces {
      name = "Test-Certs"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "Certs" {
  source = "../Certs_BP"
}

module "Certs_CC" {
  source = "../Certs_CC"
}