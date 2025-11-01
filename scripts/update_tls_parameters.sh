#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: update_tls_parameters.sh --cert-path <fullchain.pem> --key-path <privkey.pem> \
       --cert-parameter <ssm-parameter-name> --key-parameter <ssm-parameter-name>

Base64-encodes the provided TLS certificate and key, then stores them as SecureString
parameters in AWS Systems Manager Parameter Store. Existing parameters are overwritten.

Required arguments:
  --cert-path         Path to the certificate chain file (e.g., fullchain.pem).
  --key-path          Path to the private key file (e.g., privkey.pem).
  --cert-parameter    Name of the SSM parameter to store the certificate blob.
  --key-parameter     Name of the SSM parameter to store the key blob.

Example:
  ./scripts/update_tls_parameters.sh \
    --cert-path /tmp/fullchain.pem \
    --key-path /tmp/privkey.pem \
    --cert-parameter /demo/jira/cert \
    --key-parameter /demo/jira/key
EOF
}

cert_path=""
key_path=""
cert_parameter=""
key_parameter=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --cert-path)
      cert_path="$2"
      shift 2
      ;;
    --key-path)
      key_path="$2"
      shift 2
      ;;
    --cert-parameter)
      cert_parameter="$2"
      shift 2
      ;;
    --key-parameter)
      key_parameter="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$cert_path" ] || [ -z "$key_path" ] || [ -z "$cert_parameter" ] || [ -z "$key_parameter" ]; then
  echo "All arguments are required." >&2
  usage >&2
  exit 1
fi

if [ ! -f "$cert_path" ]; then
  echo "Certificate file not found: $cert_path" >&2
  exit 1
fi

if [ ! -f "$key_path" ]; then
  echo "Key file not found: $key_path" >&2
  exit 1
fi

cert_b64=$(base64 "$cert_path" | tr -d '\n')
key_b64=$(base64 "$key_path" | tr -d '\n')

aws ssm put-parameter \
  --name "$cert_parameter" \
  --type SecureString \
  --value "$cert_b64" \
  --overwrite

aws ssm put-parameter \
  --name "$key_parameter" \
  --type SecureString \
  --value "$key_b64" \
  --overwrite

echo "Updated certificate parameter: $cert_parameter"
echo "Updated key parameter: $key_parameter"
