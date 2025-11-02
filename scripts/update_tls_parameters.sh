#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: update_tls_parameters.sh [--cert-path <fullchain.pem>] [--key-path <privkey.pem>] \
       [--cert-parameter <ssm-parameter-name>] [--key-parameter <ssm-parameter-name>] [--truncate-after-upload]

Base64-encodes the provided TLS certificate and key, then stores them as SecureString
parameters in AWS Systems Manager Parameter Store. Existing parameters are overwritten.

Defaults:
  --cert-path         certs/fullchain.pem
  --key-path          certs/privkey.pem
  --cert-parameter    /demo/jira/cert
  --key-parameter     /demo/jira/key

Optional arguments:
  --truncate-after-upload  Truncate the certificate and key files after successful upload.

Example (using defaults):
  ./scripts/update_tls_parameters.sh --truncate-after-upload
EOF
}

cert_path="certs/fullchain.pem"
key_path="certs/privkey.pem"
cert_parameter="/demo/jira/cert"
key_parameter="/demo/jira/key"
truncate_after_upload="false"

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
    --truncate-after-upload)
      truncate_after_upload="true"
      shift 1
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

if [ "$truncate_after_upload" = "true" ]; then
  : > "$cert_path"
  : > "$key_path"
  echo "Truncated source files: $cert_path, $key_path"
fi
