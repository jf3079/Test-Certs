"""
Export an ACM certificate (body, chain, private key) from the source account and
store it as a single JSON secret in AWS Secrets Manager in the destination account.

Secret value (JSON):
  {"certificate_body": "...", "certificate_chain": "...", "private_key": "..."}

Usage: python3 export_cert_to_secret.py <config.json>
Config keys: cert_arn, source_region, dest_account_id, dest_region, role_name,
             secret_name (passphrase secret in source), secret_prefix (optional)
"""
import hashlib
import json
import os
import sys

import boto3
from botocore.exceptions import ClientError
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization


def load_config(path):
    if not os.path.exists(path):
        raise FileNotFoundError(f"Config not found at {path}")
    with open(path, "r") as f:
        return json.load(f)


def get_passphrase(secret_id, region):
    client = boto3.client("secretsmanager", region_name=region)
    try:
        val = client.get_secret_value(SecretId=secret_id)["SecretString"]
    except Exception as e:
        print(f"Critical: Could not retrieve passphrase secret '{secret_id}': {e}")
        sys.exit(1)
    try:
        return json.loads(val)["passphrase"].encode("utf-8")
    except (json.JSONDecodeError, KeyError, TypeError):
        return val.encode("utf-8")


def to_text(x):
    return x.decode("utf-8") if isinstance(x, bytes) else x


def secret_name_for(prefix, domain):
    # Secrets Manager names allow [A-Za-z0-9/_+=.@-]; "*" is not allowed
    safe = domain.replace("*", "star")
    return f"{prefix.strip('/')}/{safe}"


def fingerprint(payload):
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()


def upsert_secret(sm, name, payload, tags):
    new_string = json.dumps(payload)
    try:
        current = sm.get_secret_value(SecretId=name)["SecretString"]
        if fingerprint(json.loads(current)) == fingerprint(payload):
            return "SKIP"
        sm.put_secret_value(SecretId=name, SecretString=new_string)
        return "UPDATE"
    except ClientError as e:
        if e.response["Error"]["Code"] != "ResourceNotFoundException":
            raise
    sm.create_secret(
        Name=name,
        Description="Exported ACM certificate (body, chain, private key)",
        SecretString=new_string,
        Tags=tags,
    )
    return "NEW"


def main(config_path):
    cfg = load_config(config_path)
    prefix = cfg.get("secret_prefix", "acm-export")
    dest_region = cfg["dest_region"]
    role_arn = f"arn:aws:iam::{cfg['dest_account_id']}:role/{cfg['role_name']}"

    print(f"\n[PROCESS] {cfg['cert_arn']} -> {cfg['dest_account_id']}/{dest_region}")

    source_acm = boto3.client("acm", region_name=cfg["source_region"])
    try:
        cert = source_acm.describe_certificate(CertificateArn=cfg["cert_arn"])["Certificate"]
        domain = cert["DomainName"]
    except Exception as e:
        print(f"FAILED: describe source certificate: {e}")
        sys.exit(1)

    passphrase = get_passphrase(cfg["secret_name"], cfg["source_region"])
    try:
        exp = source_acm.export_certificate(CertificateArn=cfg["cert_arn"], Passphrase=passphrase)
        key_obj = serialization.load_pem_private_key(
            to_text(exp["PrivateKey"]).encode(), password=passphrase, backend=default_backend()
        )
        private_key = key_obj.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.TraditionalOpenSSL,
            encryption_algorithm=serialization.NoEncryption(),
        ).decode()
    except Exception as e:
        print(f"FAILED: export/decrypt: {e}")
        sys.exit(1)

    payload = {
        "certificate_body": to_text(exp["Certificate"]),
        "certificate_chain": to_text(exp.get("CertificateChain", "")),
        "private_key": private_key,
    }

    try:
        creds = boto3.client("sts", region_name=dest_region).assume_role(
            RoleArn=role_arn, RoleSessionName="CertSecretExport"
        )["Credentials"]
    except Exception as e:
        print(f"FAILED: assume {role_arn}: {e}")
        sys.exit(1)

    sm = boto3.client(
        "secretsmanager",
        region_name=dest_region,
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
    )

    name = secret_name_for(prefix, domain)
    tags = [
        {"Key": "SourceCertificateArn", "Value": cfg["cert_arn"]},
        {"Key": "Domain", "Value": domain},
        {"Key": "ManagedBy", "Value": "terraform-export_cert_to_secret"},
    ]
    try:
        result = upsert_secret(sm, name, payload, tags)
    except Exception as e:
        print(f"FAILED: write secret '{name}': {e}")
        sys.exit(1)
    print(f"{result}: secret '{name}' in {cfg['dest_account_id']}/{dest_region}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "config.json")
