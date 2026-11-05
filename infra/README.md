# infra

Terraform for this project's AWS infrastructure: a single EC2 instance (Ubuntu 24.04 + Docker)
in the default VPC, with an Elastic IP, a security group for HTTP/HTTPS, and an IAM role
for SSM Session Manager access. It also manages the GitHub repo's deploy settings: the
`production` environment and the Actions variables the workflows read.

## Layout

| Path | What it is |
|---|---|
| `infra/` | Main root module: the app infrastructure. State lives in S3 (see below). |
| `infra/project.auto.tfvars` | The project's identity: AWS account, region, name, GitHub repo. Every module loads it (`bootstrap/` and `account/` link to it). |
| `infra/bootstrap/` | Creates the S3 state bucket. Uses **local** state, committed to git. |
| `infra/backend.hcl` | State bucket and region, shared by `infra/` and `infra/account/`. Written by bootstrap. |
| `infra/account/` | Account access: an IAM Identity Center admin user and group. State in S3. |
| `infra/user-data.sh.tftpl` | First-boot script (swap, Docker, `/opt/app`). Editing it **replaces the instance**. |

Each directory is its own root module: run Terraform from inside it (or with
`terraform -chdir=<dir> ...`) and `terraform init` each one separately.

## Prerequisites

- **Terraform**, at the version pinned in `.terraform-version`.
- **AWS CLI v2**, with an SSO profile for the admin user (created in first-time setup).
- **[Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)** for shell access to the instance.
- **[just](https://just.systems/man/en/)** for the project tasks in the repo-root `justfile`.
- **[GitHub CLI](https://cli.github.com/)** (`gh`), logged in as a repo admin. The main module's
  GitHub provider uses its token: `just` recipes pass it as `GITHUB_TOKEN`; when running
  `terraform` directly, `export GITHUB_TOKEN=$(gh auth token)` first.

### AWS credentials

Terraform and the AWS CLI use the `default` profile, or the one named by `AWS_PROFILE` if
you export it. Every module stops before doing anything if the credentials belong to an
account other than `account_id` in `project.auto.tfvars`.

## First-time setup

Start by filling in `infra/project.auto.tfvars`. In a copy of this repo, also delete
`infra/bootstrap/terraform.tfstate` and `infra/backend.hcl`: they describe the original's
state bucket.

If these modules were initialized before against a different bucket (an earlier setup that
was torn down, or a working copy reused for a new project), delete each module's
`.terraform/` directory first, or pass `-reconfigure` to `terraform init`. Otherwise `init`
reports that the cached backend configuration has changed.

Steps 1–4 run as the account's root user, once. Everything after runs as the admin identity.

1. **Create the state bucket**
   ```sh
   cd infra/bootstrap
   terraform init
   terraform plan -out=tfplan
   terraform apply tfplan
   git add terraform.tfstate && git commit -m "Bootstrap Terraform state bucket"
   ```
2. **Point the other modules at it**
   ```sh
   terraform output -raw backend_hcl > ../backend.hcl
   git add ../backend.hcl && git commit -m "Point Terraform backends at the state bucket"
   ```
3. **Enable IAM Identity Center** in the console, in the project's `region`. This can't be done from
   Terraform.
4. **Create the admin user**
   ```sh
   cd infra/account
   cp terraform.tfvars.example terraform.tfvars   # fill in; gitignored
   terraform init -backend-config=../backend.hcl
   terraform plan -out=tfplan
   terraform apply tfplan
   ```
5. **Finish the admin user in the console** (IAM Identity Center → Users): send the
   password setup email, sign in at the access portal (`terraform output sso_start_url`),
   and enroll MFA.
6. **Switch the CLI to the admin identity**
   ```sh
   aws configure sso      # values from `terraform output`; name the profile `default`,
                          # or name it anything and export AWS_PROFILE=<name>
   aws logout             # drop the root credentials from `aws login`
   aws sso login
   aws sts get-caller-identity   # should show AWSReservedSSO_AdministratorAccess_..., not root
   ```
   From here on, don't use root. Make sure it has MFA and no access keys.
7. **Create the main infrastructure**
   ```sh
   just init    # add -migrate-state if it reports existing local state
   just plan
   just apply
   ```
   Besides AWS, this sets up the GitHub repo for the workflows: the `production`
   environment (you as required reviewer, `main` only) and the Actions variables they read.
   From here on, follow the workflow below.

## Workflow: apply, then commit

While Terraform is run by one person from a laptop, changes are applied **before** they
are committed or merged. A PR review would add nothing here, since the plan is the review.

**Rule: `main` always matches what is deployed.** Never leave applied changes uncommitted,
and never commit unapplied changes to `main`.

### Small changes (directly on `main`)

```sh
terraform plan                   # expect "No changes": no drift, nothing half-applied
# edit .tf files
terraform fmt && terraform validate
terraform plan -out=tfplan       # read it; look hard at "must be replaced" and "destroy"
terraform apply tfplan           # applies exactly what was reviewed
git add -A && git commit         # immediately, describing the infrastructure change
```

### Larger or exploratory changes (on a branch)

1. `git switch -c <topic>`, then apply from the branch as often as needed using the loop above.
2. **Merge to `main` as soon as the change settles.** While a branch has live changes, `main`
   is out of date, and applying from `main` would undo the branch's work.
3. Have **at most one branch with live changes** at a time. Before applying from anywhere else,
   merge it or roll it back (`git switch main && terraform apply`).

### When things go sideways

- **Apply fails partway.** State records whatever was created. Fix the code, `plan` again
  (it shows only what remains), apply, then commit. Don't revert to retry; the code should
  match what's now deployed.
- **`plan` shows changes you didn't make (drift).** Someone changed something in the console.
  Either add that change to the code, or apply to undo it.
- **Bootstrap changes** follow the same loop. Commit the updated `bootstrap/terraform.tfstate`
  along with the code.

### Things that replace the instance

These destroy the server and create a new one (new root disk; the Elastic IP moves over):

- editing `user-data.sh.tftpl` or its inputs (e.g. `swap_size_mb`)
- `terraform apply -replace=aws_instance.app` (also the way to adopt a newer Ubuntu AMI,
  which is otherwise ignored)
- some instance argument changes. The plan says `must be replaced`.

### Renaming the GitHub repo

The deploy roles trust GitHub's OIDC tokens only when they come from this repo, and those
tokens include the repo's name. After a rename, deploys fail until the roles are updated:

1. Rename the repo, then `git remote set-url origin <new URL>`.
2. Set `github_repository` in `project.auto.tfvars` to the new name, then plan and apply.
   Expect in-place updates to the roles' trust policies and nothing replaced.

Do this before anything else takes the old name. GitHub redirects the old name to the new
one only until another repo claims it. After that, the old name refers to the other repo.

## Tearing down

Destroy in the reverse order of setup: main module, then account, then bootstrap. Each one's
state or credentials depend on the next.

1. **Main module**, as the admin identity. Do this while `github_repository` still names
   the repo, because it also deletes the `production` environment and Actions variables.
   ```sh
   just plan -destroy
   just apply
   ```
   ECR repos are deleted along with their images. The Elastic IP is released, so a new
   setup gets a different public IP (update any DNS records).
2. **Account module**, as the **root user** (`aws login`). This deletes the admin identity,
   including the `AWSReservedSSO_AdministratorAccess_...` role behind your SSO session,
   so the admin can't run it. It needs `terraform.tfvars` from setup step 4.
   ```sh
   cd infra/account
   terraform plan -destroy -out=tfplan
   terraform apply tfplan
   ```
   IAM Identity Center itself stays enabled. To disable it, use the console.
3. **Bootstrap**, as root. The bucket is protected twice: `prevent_destroy` makes Terraform
   refuse, and S3 won't delete a bucket that still holds objects. It is versioned, so it
   still holds every earlier state version. Remove both protections with one apply, then
   destroy:
   1. In `bootstrap/main.tf`, delete the `lifecycle { prevent_destroy = true }` block from
      `aws_s3_bucket.tfstate`, and add `force_destroy = true` (which deletes all object
      versions on destroy).
   2. Apply, then destroy:
      ```sh
      cd infra/bootstrap
      terraform plan -out=tfplan      # expect an in-place update to force_destroy only
      terraform apply tfplan
      terraform plan -destroy -out=tfplan
      terraform apply tfplan
      ```
   3. Commit the edits and the now-empty `terraform.tfstate`. `main` then matches what's
      deployed: nothing. Before setting up again, restore `prevent_destroy`, remove
      `force_destroy`, and follow [First-time setup](#first-time-setup), including deleting
      the old state file and `backend.hcl`.

To set up again, also redo setup step 5. The new admin user is a new identity, so it needs
the password setup email and MFA enrollment again.

## Project tasks (`just`)

The repo-root `justfile` wraps the commands above for the main module. Recipes work
from any directory in the repo, log in to AWS SSO first if the session has expired, and
print each command before running it.

```sh
just                 # list recipes
just init            # terraform init against the S3 backend (extra args pass through)
just plan            # terraform plan -out=tfplan (extra args pass through)
just apply           # terraform apply tfplan, after a confirmation prompt
just ssm             # shell on the instance via SSM Session Manager
just live            # release each running container was started from (via SSM Run Command)
just --dry-run plan  # show the commands without running them
```

The bootstrap and account modules are run by hand, as in first-time setup.

## Useful commands

```sh
terraform output                                 # public_ip (Elastic IP), instance_id, ...
$(terraform output -raw ssm_session_command)     # shell on the instance (or: just ssm)
```

On the instance, check first-boot setup with `cloud-init status --long` and
`sudo tail -100 /var/log/cloud-init-output.log`.

## Revisit when adding CI/CD

Once CI runs Terraform (or a second person does), switch to: **plan on PR → review the code
and the plan → apply from CI after merge**, and stop applying from laptops. The S3 backend's
lock file (`use_lockfile = true`) already prevents concurrent applies.
