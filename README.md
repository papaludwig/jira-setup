# Jira Demo Setup Automation

Automation for provisioning an AWS-hosted Jira Data Center demo environment with
CloudFormation for infrastructure and AWS Systems Manager Automation +
Ansible for in-guest configuration. Everything can be launched from a
browser-based environment such as AWS CloudShell without installing Terraform.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `cloudformation/` | CloudFormation templates for the core infrastructure. |
| `automation/` | Systems Manager Automation documents used to run Ansible. |
| `ansible/` | Playbooks and roles that configure the EC2 instance locally. |
| `scripts/bootstrap.sh` | Orchestrates packaging, CloudFormation deploy, and Automation execution. |
| `scripts/package_ansible.sh` | Creates/upload the Ansible bundle consumed by AWS-RunAnsiblePlaybook. |
| `docs/` | Design notes and operational runbooks. |

## Prerequisites

Run from an environment that has:

- AWS CLI v2 configured with credentials that can manage EC2, IAM, S3, SSM, and CloudFormation resources in the target account.
- `jq`, `zip`, and `rsync` installed (CloudShell includes them by default).
- An S3 bucket to store the packaged Ansible bundle.
- Pre-created networking primitives referenced by the stack: VPC, subnet, and Elastic IP allocation.
- Jira artifacts and secrets available:
  - Jira tarball download URL.
  - Jira PostgreSQL password (SecureString in Parameter Store recommended).
  - Base64-encoded TLS certificate chain and key.

## Initial Setup

1. Retrieve this repository in your execution environment. When running from
   CloudShell, `curl` works even if `git` is unavailable:

   ```bash
   curl -L https://github.com/example-org/jira-setup/archive/refs/heads/main.tar.gz | tar -xz
   mv jira-setup-main jira-setup
   cd jira-setup
   ```

   Substitute `example-org` with the GitHub organization or user that hosts the
   repository if it differs.

2. Create the S3 bucket that will hold the packaged Ansible bundle. The helper
   script below provisions `demo-artifacts` in `us-east-1`, enables versioning
   and default encryption, and blocks public access:

   ```bash
   ./scripts/create_artifact_bucket.sh --bucket demo-artifacts --region us-east-1
   ```

   The script is idempotent; rerunning it simply reapplies the secure settings
   if the bucket already exists.

3. (Optional) Build the bucket manually with the AWS CLI instead of using the
   helper script:

   ```bash
   aws s3api create-bucket --bucket demo-artifacts --region us-east-1
   aws s3api put-bucket-versioning --bucket demo-artifacts --versioning-configuration Status=Enabled --region us-east-1
   aws s3api put-bucket-encryption --bucket demo-artifacts \
     --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
     --region us-east-1
   aws s3api put-public-access-block --bucket demo-artifacts \
     --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
     --region us-east-1
   ```

## Quick Start

1. Clone or download this repository in your execution environment.
2. Export the required secrets in the shell that will run the automation (these
   examples pull from Parameter Store):

   ```bash
   export JIRA_TARBALL_URL="https://www.atlassian.com/software/jira/downloads/binary/atlassian-jira-software-10.7.4.tar.gz"
   export JIRA_DB_PASSWORD="$(aws ssm get-parameter --name /demo/jira/db_password --with-decryption --query Parameter.Value --output text)"
   export JIRA_TLS_CERT_B64="$(aws ssm get-parameter --name /demo/jira/cert --with-decryption --query Parameter.Value --output text)"
   export JIRA_TLS_KEY_B64="$(aws ssm get-parameter --name /demo/jira/key --with-decryption --query Parameter.Value --output text)"
   ```

3. Run the bootstrap script, supplying the CloudFormation parameters that vary
   per environment. The example below assumes a VPC, subnet, and Elastic IP are
   already provisioned and that `demo-artifacts` is the S3 bucket where the
   Ansible bundle should reside:

   ```bash
   ./scripts/bootstrap.sh \
     --stack-name jira-demo \
     --bucket demo-artifacts \
     --region us-east-1 \
     --parameter VpcId=vpc-0e2b7d69 \
     --parameter SubnetId=subnet-4a11f267 \
     --parameter ElasticIpAllocationId=eipalloc-0938e39b8988b3bc5
   ```

   The script performs the following:

   - Packages `ansible/` into a zip archive and uploads it to the specified S3 bucket.
   - Creates or updates the `Jira-SetupBootstrap` Automation document in Systems Manager.
   - Deploys/updates the CloudFormation stack defined in `cloudformation/jira.yaml`.
   - Starts the Automation execution, which downloads the bundle to the EC2
     instance and runs `ansible/playbooks/site.yml` locally via `AWS-RunAnsiblePlaybook`.

4. Monitor the Automation execution from the Systems Manager console (Automation
   section) or by polling with the AWS CLI:

   ```bash
   aws ssm get-automation-execution \
     --automation-execution-id <execution-id-from-bootstrap> \
     --region us-west-2 \
     --query 'AutomationExecution.{Status:AutomationExecutionStatus,Outputs:Outputs}'
   ```

5. When the Automation run reports `Success`, browse to `https://<elastic-ip>/`
   to complete the Jira setup wizard. Capture an AMI if you need a reusable
   snapshot for future classrooms or demos.

## CloudFormation Parameters

| Parameter | Description |
| --- | --- |
| `VpcId` | Target VPC for the Jira instance. |
| `SubnetId` | Subnet inside the VPC where the instance launches. |
| `ElasticIpAllocationId` | Allocation ID of the Elastic IP that should be attached. |
| `AnsibleArtifactBucket` | S3 bucket that hosts the Ansible bundle (populated automatically by `bootstrap.sh`). |
| `NamePrefix` | Prefix applied to named AWS resources (default `jira-demo`). |
| `DeploymentId` | Tag used for resource grouping (defaults to stack name). |
| `InstanceType` | EC2 instance size (default `m6i.xlarge`). |
| `RootVolumeSize` | Root EBS volume size in GiB (default `100`). |
| `AnsibleUser` | OS user created for automation tasks (default `ansible`). |
| `AmiParameterName` | SSM parameter that resolves to the desired Amazon Linux AMI. |
| `AllowHttpsCidr` | CIDR allowed to reach Jira over HTTPS (default `0.0.0.0/0`). |

Most parameters have reasonable defaults; only the networking resources and EIP
allocation are mandatory overrides.

## Systems Manager Automation

The Automation document (`automation/jira-bootstrap.yaml`) looks up the EC2
instance created by CloudFormation, builds a JSON blob of Ansible extra
variables, and invokes the managed `AWS-RunAnsiblePlaybook` document against the
instance. The playbook runs **on the instance itself** using a local inventory,
so no control node is required and CloudShell disk usage remains minimal.

You can register or update the document manually if preferred:

```bash
aws ssm create-document \
  --name Jira-SetupBootstrap \
  --document-type Automation \
  --document-format YAML \
  --content file://automation/jira-bootstrap.yaml
```

If the document already exists, switch to `aws ssm update-document` followed by
`aws ssm update-document-default-version`.

## Manual Validation

Because the workflow targets live AWS resources, automated tests are not
included. Validate changes by running the bootstrap process in a non-production
AWS account and confirming:

1. The CloudFormation stack reaches `CREATE_COMPLETE` or `UPDATE_COMPLETE`.
2. The Automation execution finishes with status `Success`.
3. Jira responds with HTTPS on port 443 through the attached Elastic IP.
4. Optional: capture an AMI for reuse once Jira is configured.

Document validation runs (date, region, execution ID) in pull request notes to
maintain traceability.

## Managing Secrets

Use the helper scripts under `scripts/` to maintain secrets in Parameter Store:

- `./scripts/update_db_password.sh` – create or rotate the Jira database password.
- `./scripts/update_tls_parameters.sh` – upload refreshed TLS certificate and key
  material and optionally wipe local files afterward.

Export the retrieved values into environment variables immediately before
running `bootstrap.sh`, or pass Parameter Store lookups inline (e.g.
`export JIRA_DB_PASSWORD="$(aws ssm get-parameter ...)"`).

## Cleaning Up

To tear down the environment:

1. Stop any running Automation executions.
2. Delete the CloudFormation stack:

   ```bash
   aws cloudformation delete-stack --stack-name jira-demo --region us-west-2
   aws cloudformation wait stack-delete-complete --stack-name jira-demo --region us-west-2
   ```

3. Remove the uploaded Ansible bundle from S3 if it is no longer needed.
4. Optionally delete the `Jira-SetupBootstrap` Automation document:

   ```bash
   aws ssm delete-document --name Jira-SetupBootstrap --region us-west-2
   ```

This returns the account to its pre-deployment state while preserving reusable
artifacts such as the S3 bucket and Parameter Store secrets.
