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
- Terraform ≥ 1.6 and Ansible ≥ 2.15 installed (AWS CloudShell already includes both).
- Jira download URL, database password, and TLS materials accessible as environment variables.
- The `amazon.aws`, `community.postgresql`, and `community.general` Ansible collections (`ansible-galaxy collection install amazon.aws community.postgresql community.general`).

## Getting the Repository in AWS CloudShell

AWS CloudShell persists the contents of your home directory across sessions, so you typically only need to download the code once per region. If you start in a brand-new environment—or want to refresh to the latest commit—use `curl` to grab the repository tarball and extract it:

```bash
curl -L https://github.com/<your-org>/jira-setup/archive/refs/heads/main.tar.gz | tar -xz
cd jira-setup-main
```

Replace `jira-setup-main` with the extracted directory name if the default branch changes. Future CloudShell sessions can simply `cd` into the persisted directory.

## Quick Start

1. Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and fill in the AWS-specific values (VPC, subnet, Elastic IP allocation, sizing, etc.).
2. Export required secrets in the shell that will run the automation:

   ```bash
   export JIRA_TARBALL_URL="https://downloads.atlassian.com/software/jira/downloads/atlassian-jira-software-10.1.0.tar.gz"
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

Whenever you renew the Let’s Encrypt wildcard certificate, update the SecureString parameters so future runs deploy the new files. The helper script below base64-encodes your `fullchain.pem` and `privkey.pem` and writes them to Parameter Store:

```bash
./scripts/update_tls_parameters.sh \
  --cert-path /path/to/fullchain.pem \
  --key-path /path/to/privkey.pem \
  --cert-parameter /demo/jira/cert \
  --key-parameter /demo/jira/key
```

The script overwrites the existing values with the freshly encoded blobs, matching what `bootstrap.sh` expects when exporting `JIRA_TLS_CERT_B64` and `JIRA_TLS_KEY_B64`.
