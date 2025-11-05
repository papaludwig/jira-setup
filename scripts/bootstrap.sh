#!/usr/bin/env bash
set -euo pipefail

export AWS_PAGER=""

DEBUG_BOOTSTRAP_FLAG=${DEBUG_BOOTSTRAP:-}
if [[ -n ${DEBUG_BOOTSTRAP_FLAG} ]]; then
  set -x
fi

AWS_DEBUG_ARGS=()
QUIET_BOOTSTRAP=true
if [[ -n ${DEBUG_BOOTSTRAP_FLAG} ]]; then
  AWS_DEBUG_ARGS+=(--debug)
  QUIET_BOOTSTRAP=false
fi

aws_cli() {
  aws "${AWS_DEBUG_ARGS[@]}" "$@"
}

usage() {
  cat <<'USAGE'
Usage: bootstrap.sh --stack-name <name> --bucket <s3-bucket> [options]

Automates the CloudFormation deployment and SSM Automation run to provision and
configure the Jira demo environment without requiring Terraform.

Required environment variables:
  JIRA_TARBALL_URL   HTTPS URL to the Jira installer tarball.
  JIRA_DB_PASSWORD   Password for the Jira PostgreSQL user.
  JIRA_TLS_CERT_B64  Base64-encoded TLS certificate chain for nginx.
  JIRA_TLS_KEY_B64   Base64-encoded TLS private key matching the certificate.

Optional environment variables:
  DEBUG_BOOTSTRAP    When set, enables shell tracing and AWS CLI --debug output.

Options:
  --stack-name VALUE         CloudFormation stack name. (required)
  --bucket VALUE             S3 bucket that stores the Ansible bundle. (required)
  --region VALUE             AWS region for all operations (defaults to AWS CLI config).
  --template FILE            Path to the CloudFormation template (default: cloudformation/jira.yaml).
  --parameter NAME=VALUE     Override/add a CloudFormation template parameter. May be repeated.
  --deployment-id VALUE      Tag/identifier applied to resources (default: stack name).
  --ansible-user VALUE       OS user created by CloudFormation (default: ansible).
  --ansible-prefix VALUE     S3 key prefix for uploaded Ansible bundles (default: jira-ansible/).
  --ansible-key VALUE        Explicit S3 object key for the Ansible bundle (overrides prefix).
  --automation-document NAME SSM Automation document name (default: Jira-SetupBootstrap).
  --skip-stack               Skip CloudFormation deployment (assumes stack already exists).
  --skip-upload              Skip packaging/uploading Ansible (assumes bundle already present).
  -h, --help                 Show this help message.
USAGE
}

STACK_NAME=""
S3_BUCKET=""
REGION=""
TEMPLATE="cloudformation/jira.yaml"
DEPLOYMENT_ID=""
ANSIBLE_USER="ansible"
ANSIBLE_PREFIX="jira-ansible/"
ANSIBLE_KEY=""
AUTOMATION_DOCUMENT="Jira-SetupBootstrap"
SKIP_STACK=false
SKIP_UPLOAD=false
PARAMETERS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack-name)
      STACK_NAME="$2"
      shift 2
      ;;
    --bucket)
      S3_BUCKET="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --template)
      TEMPLATE="$2"
      shift 2
      ;;
    --parameter)
      PARAMETERS+=("$2")
      shift 2
      ;;
    --deployment-id)
      DEPLOYMENT_ID="$2"
      shift 2
      ;;
    --ansible-user)
      ANSIBLE_USER="$2"
      shift 2
      ;;
    --ansible-prefix)
      ANSIBLE_PREFIX="$2"
      shift 2
      ;;
    --ansible-key)
      ANSIBLE_KEY="$2"
      shift 2
      ;;
    --automation-document)
      AUTOMATION_DOCUMENT="$2"
      shift 2
      ;;
    --skip-stack)
      SKIP_STACK=true
      shift
      ;;
    --skip-upload)
      SKIP_UPLOAD=true
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

if [[ -z ${STACK_NAME} ]]; then
  echo "--stack-name is required." >&2
  usage >&2
  exit 1
fi

if [[ -z ${S3_BUCKET} ]]; then
  echo "--bucket is required." >&2
  usage >&2
  exit 1
fi

for cmd in aws jq; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Required command not found in PATH: ${cmd}" >&2
    exit 1
  fi
done

if [[ -z ${REGION} ]]; then
  REGION=$(aws_cli configure get region 2>/dev/null || true)
fi

if [[ -z ${REGION} ]]; then
  echo "Unable to determine AWS region. Provide --region or configure a default." >&2
  exit 1
fi

declare -a REQUIRED_ENV=(JIRA_TARBALL_URL JIRA_DB_PASSWORD JIRA_TLS_CERT_B64 JIRA_TLS_KEY_B64)
for var in "${REQUIRED_ENV[@]}"; do
  if [[ -z ${!var:-} ]]; then
    echo "Environment variable ${var} must be set." >&2
    exit 1
  fi
done

if [[ -z ${DEPLOYMENT_ID} ]]; then
  DEPLOYMENT_ID="${STACK_NAME}"
fi

if [[ ${SKIP_UPLOAD} == true ]]; then
  if [[ -z ${ANSIBLE_KEY} ]]; then
    echo "Provide --ansible-key when using --skip-upload so the existing bundle can be referenced." >&2
    exit 1
  fi
else
  if [[ -z ${ANSIBLE_KEY} ]]; then
    timestamp=$(date +%Y%m%d%H%M%S)
    trimmed_prefix=${ANSIBLE_PREFIX%/}
    ANSIBLE_KEY="${trimmed_prefix}/ansible-${timestamp}.zip"
  fi
  ./scripts/package_ansible.sh --bucket "${S3_BUCKET}" --key "${ANSIBLE_KEY}" 1>&2
  # keep ANSIBLE_KEY as computed earlier (timestamp-based)
fi

ensure_automation_document() {
  local name="${AUTOMATION_DOCUMENT}"
  local content="automation/jira-bootstrap.yaml"
  if [[ ${QUIET_BOOTSTRAP} == true ]]; then
    if aws_cli ssm describe-document --name "${name}" --region "${REGION}" >/dev/null 2>&1; then
      aws_cli ssm update-document \
        --name "${name}" \
        --region "${REGION}" \
        --content "file://${content}" \
        --document-format YAML \
        --document-version '$LATEST' >/dev/null
      aws_cli ssm update-document-default-version \
        --name "${name}" \
        --region "${REGION}" \
        --document-version "\$LATEST" >/dev/null
    else
      aws_cli ssm create-document \
        --name "${name}" \
        --region "${REGION}" \
        --content "file://${content}" \
        --document-type Automation \
        --document-format YAML >/dev/null
    fi
  else
    if aws_cli ssm describe-document --name "${name}" --region "${REGION}"; then
      aws_cli ssm update-document \
        --name "${name}" \
        --region "${REGION}" \
        --content "file://${content}" \
        --document-format YAML \
        --document-version '$LATEST'
      aws_cli ssm update-document-default-version \
        --name "${name}" \
        --region "${REGION}" \
        --document-version "\$LATEST"
    else
      aws_cli ssm create-document \
        --name "${name}" \
        --region "${REGION}" \
        --content "file://${content}" \
        --document-type Automation \
        --document-format YAML
    fi
  fi
}

ensure_automation_document

has_parameter_override() {
  local needle="$1="
  for param in "${PARAMETERS[@]}"; do
    if [[ ${param} == ${needle}* ]]; then
      return 0
    fi
  done
  return 1
}

if [[ ${SKIP_STACK} == false ]]; then
  if [[ ! -f ${TEMPLATE} ]]; then
    echo "Template not found: ${TEMPLATE}" >&2
    exit 1
  fi

  PARAMETER_ARGS=()
  if ! has_parameter_override "DeploymentId"; then
    PARAMETER_ARGS+=("DeploymentId=${DEPLOYMENT_ID}")
  fi
  if ! has_parameter_override "AnsibleUser"; then
    PARAMETER_ARGS+=("AnsibleUser=${ANSIBLE_USER}")
  fi
  if ! has_parameter_override "AnsibleArtifactBucket"; then
    PARAMETER_ARGS+=("AnsibleArtifactBucket=${S3_BUCKET}")
  fi
  for param in "${PARAMETERS[@]}"; do
    PARAMETER_ARGS+=("${param}")
  done

  CFN_CMD=(aws_cli cloudformation deploy)
  CFN_CMD+=(--stack-name "${STACK_NAME}")
  CFN_CMD+=(--template-file "${TEMPLATE}")
  CFN_CMD+=(--capabilities CAPABILITY_NAMED_IAM)
  CFN_CMD+=(--region "${REGION}")
  if [[ ${#PARAMETER_ARGS[@]} -gt 0 ]]; then
    CFN_CMD+=(--parameter-overrides "${PARAMETER_ARGS[@]}")
  fi
  "${CFN_CMD[@]}"
fi

AUTOMATION_PARAMS=$(jq -cn \
  --arg stack "${STACK_NAME}" \
  --arg region "${REGION}" \
  --arg bucket "${S3_BUCKET}" \
  --arg key "${ANSIBLE_KEY}" \
  --arg user "${ANSIBLE_USER}" \
  --arg download "${JIRA_TARBALL_URL}" \
  --arg dbpw "${JIRA_DB_PASSWORD}" \
  --arg cert "${JIRA_TLS_CERT_B64}" \
  --arg keyb "${JIRA_TLS_KEY_B64}" \
  '{
    StackName: [$stack],
    AnsibleS3Bucket: [$bucket],
    AnsibleS3Key: [$key],
    AnsibleUser: [$user],
    JiraDownloadUrl: [$download],
    JiraDbPassword: [$dbpw],
    JiraTlsCertB64: [$cert],
    JiraTlsKeyB64: [$keyb]
  }')

EXECUTION_ID=$(aws_cli ssm start-automation-execution \
  --region "${REGION}" \
  --document-name "${AUTOMATION_DOCUMENT}" \
  --parameters "${AUTOMATION_PARAMS}" \
  --query AutomationExecutionId \
  --output text)

echo "Started Automation execution: ${EXECUTION_ID}" >&2
echo "Ansible bundle: s3://${S3_BUCKET}/${ANSIBLE_KEY}" >&2

echo "${EXECUTION_ID}"
