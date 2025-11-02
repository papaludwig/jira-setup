# Repository Guidelines

## Scope
These rules apply to the entire repository.

## General Principles
- Model AWS infrastructure with **CloudFormation** templates stored under `cloudformation/`.
- Use **AWS Systems Manager Automation** documents under `automation/` to orchestrate post-provision steps.
- Keep configuration management in Ansible, but ensure playbooks can run locally on the target host (no control node assumptions).
- Prefer POSIX-compliant shell for helper scripts; if Bash features are required, begin scripts with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Document operational runbooks and architecture decisions in `docs/`.

## File Organization
- Place CloudFormation templates in `cloudformation/` and name them with `.yaml` extensions.
- Store Automation documents in `automation/` using YAML format compatible with `aws ssm create-document`.
- Keep Ansible content (playbooks, roles, inventory, configuration) under `ansible/`.
- Put helper scripts in `scripts/`; they should compose AWS CLI commands rather than wrapping Terraform.

## Testing & Validation
- Provide CLI snippets in documentation for validating CloudFormation stacks and Automation runs.
- When adding CloudFormation templates, run them through `cfn-lint` if available.
- When modifying YAML files, run a YAML parser locally (e.g., `ruby -ryaml -e 'YAML.load_file("path/to/file")'`) and report the command under Testing.
- Keep Ansible YAML indented with two spaces per level.
- Note any AWS resources that must pre-exist (e.g., VPC, subnet, Elastic IP) in the README.

## PR / Commit Guidance
- Write descriptive commit messages summarizing the change.
- Update `README.md` or relevant docs when user-facing behavior changes.
- Ensure the default branch remains deployable with the documented workflow.
