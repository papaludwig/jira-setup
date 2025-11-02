#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BIN_DIR="${PROJECT_ROOT}/.bin"
TF_DIR="${PROJECT_ROOT}/terraform"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
TF_VARS_FILE="${TF_DIR}/terraform.tfvars"
INVENTORY_FILE="${ANSIBLE_DIR}/inventory.ini"
AUTO_APPROVE=false
DEFAULT_TF_VERSION="1.6.6"

mkdir -p "${BIN_DIR}"
export PATH="${BIN_DIR}:${PATH}"

ensure_terraform() {
  if command -v terraform >/dev/null 2>&1; then
    return 0
  fi

  local version os arch url tmpdir
  version="${TF_VERSION:-${DEFAULT_TF_VERSION}}"

  case "$(uname -s)" in
    Linux)
      os="linux"
      ;;
    Darwin)
      os="darwin"
      ;;
    *)
      echo "Unsupported operating system for automatic Terraform install: $(uname -s)" >&2
      return 1
      ;;
  esac

  case "$(uname -m)" in
    x86_64|amd64)
      arch="amd64"
      ;;
    arm64|aarch64)
      arch="arm64"
      ;;
    *)
      echo "Unsupported architecture for automatic Terraform install: $(uname -m)" >&2
      return 1
      ;;
  esac

  for dep in curl unzip; do
    if ! command -v "${dep}" >/dev/null 2>&1; then
      echo "Missing dependency for automatic Terraform install: ${dep}" >&2
      return 1
    fi
  done

  url="https://releases.hashicorp.com/terraform/${version}/terraform_${version}_${os}_${arch}.zip"
  tmpdir=$(mktemp -d)
  trap 'rm -rf "${tmpdir}"' RETURN

  echo "Terraform not found in PATH; downloading ${version}..." >&2

  if ! curl -fsSL "${url}" -o "${tmpdir}/terraform.zip"; then
    echo "Failed to download Terraform from ${url}" >&2
    return 1
  fi

  if ! unzip -q "${tmpdir}/terraform.zip" -d "${tmpdir}"; then
    echo "Failed to extract Terraform archive" >&2
    return 1
  fi

  mv "${tmpdir}/terraform" "${BIN_DIR}/terraform"
  chmod +x "${BIN_DIR}/terraform"
  trap - RETURN
  rm -rf "${tmpdir}"

  echo "Installed Terraform ${version} to ${BIN_DIR}/terraform" >&2
}

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

if ! ensure_terraform; then
  echo "Terraform is required but could not be installed automatically." >&2
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
