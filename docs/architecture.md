# Jira Demo Automation Architecture

This repository provisions a single-node Jira Data Center demo system using Terraform for the AWS infrastructure and Ansible for in-guest configuration.

## High-level Flow

1. `scripts/bootstrap.sh` orchestrates Terraform and Ansible.
2. Terraform creates:
   - Security group permitting HTTPS (global).
   - IAM instance profile with SSM access.
   - Amazon Linux 2023 EC2 instance sized for Jira demos.
   - Elastic IP association to provide a stable public endpoint.
3. User data adds an Ansible control user and ensures the SSM agent runs.
4. Ansible playbook installs prerequisites and configures services:
   - `common` role prepares the OS, service user, and directories.
   - `java` role installs Amazon Corretto 11.
   - `postgres` role installs and configures PostgreSQL 15 with a Jira database.
   - `jira` role downloads the Jira tarball, configures application files, and installs a systemd service.
   - `tls` role terminates HTTPS via nginx with a provided certificate.
5. Jira becomes reachable on port 443 via nginx reverse proxy.

## Secrets Handling

Sensitive values (database password, TLS cert/key) are injected at runtime via environment variables consumed by the Ansible roles. Populate these in AWS Systems Manager Parameter Store or Secrets Manager, then export within the execution environment.

## AMI Capture

After the bootstrap completes successfully, you can capture an AMI:

1. Stop Jira using `sudo systemctl stop jira` to ensure clean filesystem state.
2. Create an AMI from the instance in the AWS console or CLI.
3. Optionally, relaunch the AMI, perform Jira onboarding (license, admin user), and capture a second AMI tailored for classroom use.

## Future Enhancements

- Add Terraform modules for optional ALB termination with ACM certificates.
- Extend Ansible to import a default license or seed data for demos.
- Integrate Packer to produce the AMI directly after configuration.
