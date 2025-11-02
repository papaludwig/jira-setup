# Jira Demo Automation Architecture

This repository provisions a single-node Jira Data Center demo system using
CloudFormation for AWS resources and AWS Systems Manager Automation to run the
Ansible configuration directly on the EC2 instance.

## High-level Flow

1. `scripts/bootstrap.sh` packages the Ansible content, ensures the Automation
   document exists, deploys/updates the CloudFormation stack, and triggers
   Systems Manager Automation.
2. CloudFormation (`cloudformation/jira.yaml`) creates:
   - Security group permitting HTTPS (configurable CIDR).
   - IAM instance profile with SSM access and permission to read the Ansible S3 bucket.
   - Amazon Linux 2023 EC2 instance sized for Jira demos.
   - Elastic IP association to provide a stable public endpoint.
   - User data that creates the automation user and enables the SSM agent.
3. The Automation document (`automation/jira-bootstrap.yaml`) locates the stack's
   EC2 instance, formats the Ansible extra variables, and invokes the managed
   `AWS-RunAnsiblePlaybook` document so the playbook runs locally on the host.
4. The Ansible playbook installs prerequisites and configures services:
   - `common` role prepares the OS, service user, and directories.
   - `java` role installs Amazon Corretto 11.
   - `postgres` role installs and configures PostgreSQL 15 with a Jira database.
   - `jira` role downloads the Jira tarball, configures application files, and installs a systemd service.
   - `tls` role terminates HTTPS via nginx with the provided certificate.
5. Jira becomes reachable on port 443 via nginx reverse proxy.

## Secrets Handling

Sensitive values (database password, TLS cert/key) are passed into the
Automation document as parameters and forwarded to Ansible as JSON extra
variables. Store the secrets in Systems Manager Parameter Store or AWS Secrets
Manager and resolve them before invoking `bootstrap.sh` (or provide the parameter
references directly when calling the script).

## Artifact Storage

Ansible content is zipped on demand and uploaded to an S3 bucket supplied at
runtime. The EC2 instance assumes a role that grants read access to the bucket
so the `AWS-RunAnsiblePlaybook` document can download the archive during
execution. Old archives can be pruned manually to control storage costs.

## AMI Capture

After the automation completes successfully, you can capture an AMI:

1. Stop Jira using `sudo systemctl stop jira` to ensure a clean filesystem.
2. Create an AMI from the instance in the AWS console or CLI.
3. Optionally relaunch the AMI, perform Jira onboarding (license, admin user),
   and capture a second AMI tailored for classroom use.

## Future Enhancements

- Extend the CloudFormation template to optionally create supporting resources
  (RDS, Application Load Balancer) for more complex demos.
- Parameterize S3 access further to support dedicated prefixes per environment.
- Integrate CodeBuild to execute the automation as part of a CI/CD pipeline.
