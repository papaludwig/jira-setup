# Jira Demo Setup Automation

Automation for provisioning an AWS-hosted Jira Data Center demo environment. Terraform creates the infrastructure, and Ansible configures the EC2 instance with PostgreSQL, Jira, and TLS termination.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `terraform/` | Root Terraform module for the Jira instance. |
| `ansible/` | Playbooks and roles configuring the instance. |
| `scripts/bootstrap.sh` | Orchestrates Terraform + Ansible from a single command. |
| `docs/` | Additional design and runbook documentation. |

## Prerequisites

Run from an environment with:

- AWS credentials allowing EC2, IAM, and EIP association in the target account.
- Ansible ≥ 2.15 installed (if missing, `scripts/bootstrap.sh` installs `ansible-core` into `.python/` under the project root).
- Python 3 with `pip` available if the script needs to install Ansible automatically.
- Jira download URL, database password, and TLS materials accessible as environment variables.
- The `amazon.aws`, `community.postgresql`, and `community.general` Ansible collections (`ansible-galaxy collection install amazon.aws community.postgresql community.general`).

If Terraform is not present in `PATH`, `scripts/bootstrap.sh` downloads version 1.6.6 (override with `TF_VERSION=<version>` before running the script) into `.bin/` under the project root.

## Getting the Repository in AWS CloudShell

AWS CloudShell persists the contents of your home directory across sessions, so you typically only need to download the code once per region. If you start in a brand-new environment—or want to refresh to the latest commit—use `curl` to grab the repository tarball and extract it:

```bash
curl -L https://github.com/papaludwig/jira-setup/archive/refs/heads/main.tar.gz | tar -xz
cd jira-setup-main
```

Replace `jira-setup-main` with the extracted directory name if the default branch changes. Future CloudShell sessions can simply `cd` into the persisted directory.

### Keeping Your CloudShell Copy Up to Date

If you followed the tarball approach above, the extracted directory is not a Git checkout. To refresh it later, remove the old directory and re-download the tarball:

```bash
rm -rf jira-setup-main
curl -L https://github.com/papaludwig/jira-setup/archive/refs/heads/main.tar.gz | tar -xz
```

Alternatively, clone the repository so you can update in place without re-downloading everything:

```bash
git clone https://github.com/papaludwig/jira-setup.git
cd jira-setup
# ... work normally ...
git pull --ff-only
```

The `git pull --ff-only` command fast-forwards your CloudShell copy to match the latest default-branch commit while preserving any local work.

## Quick Start

1. Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and fill in the AWS-specific values (VPC, subnet, Elastic IP allocation, sizing, etc.).
2. Export required secrets in the shell that will run the automation:

   ```bash
   export JIRA_TARBALL_URL="https://www.atlassian.com/software/jira/downloads/binary/atlassian-jira-software-10.7.4.tar.gz"
   export JIRA_DB_PASSWORD="$(aws ssm get-parameter --name /demo/jira/db_password --with-decryption --query Parameter.Value --output text)"
   export JIRA_TLS_CERT_B64="$(aws ssm get-parameter --name /demo/jira/cert --with-decryption --query Parameter.Value --output text)"
   export JIRA_TLS_KEY_B64="$(aws ssm get-parameter --name /demo/jira/key --with-decryption --query Parameter.Value --output text)"
   ```

3. From the repository root, execute the bootstrap script:

   ```bash
   ./scripts/bootstrap.sh --auto-approve
   ```

   The script runs `terraform init/apply`, captures the generated inventory, and applies `ansible/playbooks/site.yml`. Ansible connects to the instance through AWS Systems Manager Session Manager rather than SSH, so no key pair or port 22 ingress is required.

4. After the play completes, browse to `https://<elastic-ip-or-dns>/` and perform the Jira setup wizard. Capture an AMI if you want a reusable snapshot.

## Manual Validation

Because real AWS infrastructure is required, automated testing is not available in this repository. Validate changes by running the bootstrap workflow in an isolated AWS account and confirming:

1. Terraform completes without error and outputs the inventory file.
2. Ansible finishes successfully and reports changed tasks for Jira, PostgreSQL, and TLS roles.
3. Jira responds with a 200/302 over HTTPS on port 443.
4. Optional: Stop Jira and create an AMI for future reuse.

Document the validation run (timestamp, region, commit hash) in pull request notes to keep the history auditable.

## Refreshing TLS Materials

Whenever you renew the Let’s Encrypt wildcard certificate, update the SecureString parameters so future runs deploy the new files. Drop the refreshed PEM contents into the placeholder files at `certs/fullchain.pem` and `certs/privkey.pem` (they remain empty in Git history), then run the helper script below to base64-encode the files and write them to Parameter Store:

```bash
./scripts/update_tls_parameters.sh --truncate-after-upload
```

The script defaults to reading the placeholder files and updating `/demo/jira/cert` and `/demo/jira/key`, matching what `bootstrap.sh` expects when exporting `JIRA_TLS_CERT_B64` and `JIRA_TLS_KEY_B64`. Pass the `--cert-path`, `--key-path`, `--cert-parameter`, or `--key-parameter` flags if you need to override any of the defaults.

Passing `--truncate-after-upload` clears the PEM files once the parameters are updated so sensitive material is not left behind in your AWS Shell environment. Omit the flag if you prefer to retain the files locally after the upload completes.

## Managing the Jira Database Password Parameter

Store the Jira PostgreSQL password in Parameter Store so Terraform and Ansible can fetch it without hard-coding credentials. Use the helper script below to create or rotate the SecureString parameter:

```bash
./scripts/update_db_password.sh
```

The script defaults to updating `/demo/jira/db_password`, matching the value the bootstrap process reads when exporting `JIRA_DB_PASSWORD`. Provide `--parameter` to target an alternate path. If you already have the password in a file, pass `--password-file /path/to/secret.txt`; otherwise the script will prompt for the value (input is hidden and requires confirmation). You can also supply `--password` directly, though piping from a secure source is recommended if you avoid the interactive prompt.

Run the script whenever you need to rotate the database password. After updating the parameter, re-export `JIRA_DB_PASSWORD` in any shell sessions that will invoke `scripts/bootstrap.sh` so the new credential is used.
