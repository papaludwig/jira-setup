# Repository Guidelines

## Scope
These rules apply to the entire repository unless a more specific `AGENTS.md` overrides them.

## General Principles
- Prefer declarative infrastructure-as-code. Use Terraform for AWS resources and Ansible for host configuration.
- Keep shell scripts POSIX compliant unless a feature requires Bash; in that case, set `#!/usr/bin/env bash` and `set -euo pipefail`.
- Include helpful inline comments for non-obvious logic, especially around provisioning steps.
- Use Markdown tables or lists when documenting ordered procedures.

## File Organization
- Place Terraform root modules under `terraform/` and group reusable modules under `terraform/modules/`.
- Place Ansible playbooks under `ansible/playbooks/` and roles under `ansible/roles/`.
- Put helper shell scripts under `scripts/`.
- Store design notes or runbooks in `docs/`.

## Testing & Validation
- Provide a `make` target (or script) for formatting and validation where feasible.
- When adding Terraform files, run `terraform fmt` before committing.
- When adding YAML (Ansible) files, keep indentation at two spaces per level.
- Include guidance in documentation for any manual validation that must occur in AWS.

## PR / Commit Guidance
- Write descriptive commit messages summarizing the change.
- Update `README.md` or relevant docs when user-facing behavior changes.
- Default branch should remain deployable; unfinished experiments belong on feature branches.
