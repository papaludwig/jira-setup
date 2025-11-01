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
- The `community.postgresql` and `community.general` Ansible collections (`ansible-galaxy collection install community.postgresql community.general`).

## Quick Start

1. Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and fill in the AWS-specific values (subnet ID, Elastic IP allocation, SSH key, etc.).
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

   The script runs `terraform init/apply`, captures the generated inventory, and applies `ansible/playbooks/site.yml`.

4. After the play completes, browse to `https://<elastic-ip-or-dns>/` and perform the Jira setup wizard. Capture an AMI if you want a reusable snapshot.

## Manual Validation

Because real AWS infrastructure is required, automated testing is not available in this repository. Validate changes by running the bootstrap workflow in an isolated AWS account and confirming:

1. Terraform completes without error and outputs the inventory file.
2. Ansible finishes successfully and reports changed tasks for Jira, PostgreSQL, and TLS roles.
3. Jira responds with a 200/302 over HTTPS on port 443.
4. Optional: Stop Jira and create an AMI for future reuse.

Document the validation run (timestamp, region, commit hash) in pull request notes to keep the history auditable.
