import boto3
import botocore
import json
import os
import sys
import hashlib
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend

def load_config(file_path):
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"Config not found at {file_path}")
    with open(file_path, 'r') as f:
        return json.load(f)

def get_passphrase(secret_id, region):
    client = boto3.client('secretsmanager', region_name=region)
    try:
        response = client.get_secret_value(SecretId=secret_id)
        secret_data = response.get('SecretString')
        try:
            return json.loads(secret_data)['passphrase'].encode('utf-8')
        except (json.JSONDecodeError, KeyError, TypeError):
            return secret_data.encode('utf-8')
    except Exception as e:
        print(f"Critical: Could not retrieve secret '{secret_id}': {e}")
        sys.exit(1)

def get_cert_hash(cert_body):
    """Generates a SHA256 hash of the certificate body for comparison."""
    if isinstance(cert_body, str):
        cert_body = cert_body.encode('utf-8')
    return hashlib.sha256(cert_body).hexdigest()

def find_existing_cert(dest_acm, domain_name):
    """
    Finds an existing certificate by domain name and returns its ARN and Hash.
    """
    paginator = dest_acm.get_paginator('list_certificates')
    for page in paginator.paginate(CertificateStatuses=['ISSUED']):
        for cert in page['CertificateSummaryList']:
            if cert['DomainName'] == domain_name:
                arn = cert['CertificateArn']
                # Fetch the actual body to compare if it's the same version
                cert_detail = dest_acm.get_certificate(CertificateArn=arn)
                existing_hash = get_cert_hash(cert_detail['Certificate'])
                return arn, existing_hash
    return None, None

def transfer_certificate(config_path):
    config = load_config(config_path)

    source_acm = boto3.client('acm', region_name=config['source_region'])

    dest_account = config['dest_account_id']
    dest_region = config['dest_region']
    role_arn = f"arn:aws:iam::{dest_account}:role/{config['role_name']}"

    print(f"\n[PROCESS] Source ARN: {config['cert_arn']}")

    # 1. Get Source Certificate Details
    try:
        source_desc = source_acm.describe_certificate(CertificateArn=config['cert_arn'])
        domain_name = source_desc['Certificate']['DomainName']
    except Exception as e:
        print(f"FAILED: Could not describe source certificate: {e}")
        sys.exit(1)

    # 2. Assume Role in Destination - USE REGIONAL STS ENDPOINT
    try:
        # Key change: specify region_name for STS to match destination
        sts_client = boto3.client('sts', region_name=dest_region)
        creds = sts_client.assume_role(
            RoleArn=role_arn, RoleSessionName="CertTransferSession"
        )['Credentials']
    except Exception as e:
        print(f"FAILED: Could not assume role {role_arn} via {dest_region} STS: {e}")
        sys.exit(1)

    dest_acm = boto3.client(
        'acm', region_name=dest_region,
        aws_access_key_id=creds['AccessKeyId'],
        aws_secret_access_key=creds['SecretAccessKey'],
        aws_session_token=creds['SessionToken']
    )

    # 3. Export Source Certificate
    passphrase = get_passphrase(config['secret_name'], config['source_region'])
    try:
        exported = source_acm.export_certificate(
            CertificateArn=config['cert_arn'],
            Passphrase=passphrase
        )
    except Exception as e:
        print(f"FAILED: Export failed: {e}")
        sys.exit(1)

    # 4. Check if update is needed
    source_hash = get_cert_hash(exported['Certificate'])
    existing_arn, existing_hash = find_existing_cert(dest_acm, domain_name)

    if existing_arn and source_hash == existing_hash:
        print(f"SKIP: Certificate for '{domain_name}' is already up-to-date in {dest_region}.")
        return

    # 5. Decrypt Private Key for Import
    try:
        raw_key = exported['PrivateKey']
        if isinstance(raw_key, str): raw_key = raw_key.encode('utf-8')

        private_key_obj = serialization.load_pem_private_key(
            raw_key, password=passphrase, backend=default_backend()
        )

        decrypted_key_pem = private_key_obj.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.TraditionalOpenSSL,
            encryption_algorithm=serialization.NoEncryption()
        )

        to_bytes = lambda x: x.encode('utf-8') if isinstance(x, str) else x

        # 6. Import (New) or Re-import (Update)
        import_kwargs = {
            'Certificate': to_bytes(exported['Certificate']),
            'PrivateKey': decrypted_key_pem,
            'CertificateChain': to_bytes(exported['CertificateChain'])
        }

        if existing_arn:
            print(f"[UPDATE] Certificate for '{domain_name}' has changed. Re-importing to {existing_arn}...")
            import_kwargs['CertificateArn'] = existing_arn
        else:
            print(f"[NEW] Importing new certificate for '{domain_name}'...")

        import_response = dest_acm.import_certificate(**import_kwargs)
        print(f"SUCCESS! ARN: {import_response['CertificateArn']}")

    except Exception as e:
        print(f"FAILED during Import: {e}")
        sys.exit(1)

if __name__ == "__main__":
    config_file = sys.argv[1] if len(sys.argv) > 1 else 'config.json'
    transfer_certificate(config_file)