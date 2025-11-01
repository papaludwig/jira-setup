#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TF_DIR="${PROJECT_ROOT}/terraform"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
TF_VARS_FILE="${TF_DIR}/terraform.tfvars"
INVENTORY_FILE="${ANSIBLE_DIR}/inventory.ini"
AUTO_APPROVE=false

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --tfvars FILE         Path to terraform.tfvars file (default: ${TF_VARS_FILE})
  --inventory FILE      Path to write Ansible inventory (default: ${INVENTORY_FILE})
  --auto-approve        Skip interactive Terraform approval
  -h, --help            Show this help

Environment:
  JIRA_TARBALL_URL      Required. Jira tar.gz download URL.
  JIRA_DB_PASSWORD      Required. Password for Jira database user.
  JIRA_TLS_CERT_B64     Required. Base64 encoded certificate chain for TLS termination.
  JIRA_TLS_KEY_B64      Required. Base64 encoded private key matching the certificate.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tfvars)
      TF_VARS_FILE=$2
      shift 2
      ;;
    --inventory)
      INVENTORY_FILE=$2
      shift 2
      ;;
    --auto-approve)
      AUTO_APPROVE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -f ${TF_VARS_FILE} ]]; then
  echo "Terraform variables file not found: ${TF_VARS_FILE}" >&2
  exit 1
fi

for bin in terraform ansible-playbook; do
  if ! command -v "${bin}" >/dev/null 2>&1; then
    echo "Missing dependency: ${bin}" >&2
    exit 1
  fi
done

pushd "${TF_DIR}" >/dev/null
terraform init

APPLY_ARGS=(apply)
if [[ ${AUTO_APPROVE} == true ]]; then
  APPLY_ARGS+=("-auto-approve")
fi
APPLY_ARGS+=("-var-file=${TF_VARS_FILE}")
terraform "${APPLY_ARGS[@]}"

terraform output -raw ansible_inventory >"${INVENTORY_FILE}"
popd >/dev/null

echo "Wrote Ansible inventory to ${INVENTORY_FILE}"

ansible-playbook -i "${INVENTORY_FILE}" "${ANSIBLE_DIR}/playbooks/site.yml"
