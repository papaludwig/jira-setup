#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: update_db_password.sh [--parameter <ssm-parameter-name>] [--password <value>] [--password-file <path>]

Stores the Jira database password as a SecureString parameter in AWS Systems Manager Parameter Store.
Existing parameters are overwritten.

Defaults:
  --parameter       /demo/jira/db_password

Optional arguments:
  --password        Provide the new password directly as an argument (use with caution).
  --password-file   Read the password from the specified file (first line used).

If neither --password nor --password-file is supplied, the script prompts for the
password interactively (input is hidden) and asks for confirmation before storing it.

Examples:
  ./scripts/update_db_password.sh
  ./scripts/update_db_password.sh --parameter /prod/jira/db_password --password-file /secure/path/pw.txt
USAGE
}

parameter="/demo/jira/db_password"
password=""
password_file=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --parameter)
      parameter="$2"
      shift 2
      ;;
    --password)
      password="$2"
      shift 2
      ;;
    --password-file)
      password_file="$2"
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

if [ -n "$password" ] && [ -n "$password_file" ]; then
  echo "Cannot use --password and --password-file together." >&2
  exit 1
fi

if [ -n "$password_file" ]; then
  if [ ! -f "$password_file" ]; then
    echo "Password file not found: $password_file" >&2
    exit 1
  fi
  password=$(head -n 1 "$password_file")
fi

if [ -z "$password" ]; then
  read -rsp "Enter new Jira DB password: " password
  echo
  if [ -z "$password" ]; then
    echo "Password cannot be empty." >&2
    exit 1
  fi
  read -rsp "Confirm password: " confirm
  echo
  if [ "$password" != "$confirm" ]; then
    echo "Passwords do not match." >&2
    exit 1
  fi
fi

aws ssm put-parameter \
  --name "$parameter" \
  --type SecureString \
  --value "$password" \
  --overwrite

echo "Updated Jira database password parameter: $parameter"
