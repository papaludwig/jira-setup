#!/usr/bin/env bash
set -euo pipefail

useradd --create-home --shell /bin/bash ${ansible_user} || usermod -aG wheel ${ansible_user}
echo "${ansible_user} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${ansible_user}
chmod 440 /etc/sudoers.d/${ansible_user}

# Enable SSM by ensuring the agent is running
systemctl enable --now amazon-ssm-agent
