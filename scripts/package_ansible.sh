#!/usr/bin/env bash
set -euo pipefail

export AWS_PAGER=""

DEBUG_PACKAGE_FLAG=${DEBUG_PACKAGE:-${DEBUG_BOOTSTRAP:-}}
if [[ -n ${DEBUG_PACKAGE_FLAG} ]]; then
  set -x
fi

AWS_DEBUG_ARGS=()
QUIET_PACKAGE=true
if [[ -n ${DEBUG_PACKAGE_FLAG} ]]; then
  AWS_DEBUG_ARGS+=(--debug)
  QUIET_PACKAGE=false
fi

aws_cli() {
  aws "${AWS_DEBUG_ARGS[@]}" "$@"
}

usage() {
  cat <<'USAGE'
Usage: package_ansible.sh --bucket <s3-bucket> [--key <object-key>] [--prefix <key-prefix>] [--output <zip-path>]

Packages the Ansible content under ansible/ into a zip file compatible with the
AWS-RunAnsiblePlaybook document and uploads it to S3.

Options:
  --bucket VALUE       S3 bucket that will store the archive. (required)
  --key VALUE          Object key to use for the upload. Mutually exclusive with --prefix.
  --prefix VALUE       Prefix used to generate the object key. Defaults to 'jira-ansible/'.
  --output PATH        Optional path to also write the generated zip locally.
  -h, --help           Show this help text.

Environment variables:
  DEBUG_PACKAGE        Enable shell tracing and AWS CLI --debug output when set.
  DEBUG_BOOTSTRAP      Also enables debug behavior when invoking via bootstrap.sh.

Examples:
  ./scripts/package_ansible.sh --bucket instantbrains-demo-artifacts
  ./scripts/package_ansible.sh --bucket instantbrains-demo-artifacts --prefix jira/prod/ --output /tmp/jira-ansible.zip
USAGE
}

bucket=""
key=""
prefix="jira-ansible/"
prefix_overridden=false
output=""

for cmd in aws rsync zip; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Required command not found in PATH: ${cmd}" >&2
    exit 1
  fi
done

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket)
      bucket="$2"
      shift 2
      ;;
    --key)
      key="$2"
      shift 2
      ;;
    --prefix)
      prefix="$2"
      prefix_overridden=true
      shift 2
      ;;
    --output)
      output="$2"
      shift 2
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

if [[ -z ${bucket} ]]; then
  echo "--bucket is required." >&2
  usage >&2
  exit 1
fi

if [[ -n ${key} && ${prefix_overridden} == true ]]; then
  echo "Specify either --key or --prefix, not both." >&2
  exit 1
fi

if [[ -z ${key} ]]; then
  timestamp=$(date +%Y%m%d%H%M%S)
  trimmed_prefix=${prefix%/}
  key="${trimmed_prefix}/ansible-${timestamp}.zip"
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "${tmpdir}"' EXIT

if [[ ${QUIET_PACKAGE} == true ]]; then
  rsync -a --delete ansible/ "${tmpdir}/ansible/" >/dev/null
else
  rsync -a --delete ansible/ "${tmpdir}/ansible/"
fi

pushd "${tmpdir}/ansible" >/dev/null
zip_path="${tmpdir}/ansible.zip"
zip -qr "${zip_path}" .
popd >/dev/null

s3_uri="s3://${bucket}/${key}"
aws_cli s3 cp "${zip_path}" "${s3_uri}"

echo "Uploaded Ansible bundle to ${s3_uri}" >&2

echo "${key}"

if [[ -n ${output} ]]; then
  cp "${zip_path}" "${output}"
  echo "Wrote local copy to ${output}" >&2
fi
