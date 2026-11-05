# Compose on EC2

A template for running a Docker Compose application on a small AWS EC2 instance and releasing it from GitHub Actions. The repository keeps the application packaging, release workflow, and infrastructure together so a project can start with a working deployment path and adapt it as it grows.

This template currently targets AWS: Terraform provisions the instance and ECR repositories, and GitHub Actions uses AWS OIDC and Systems Manager to deploy. The application is described in `compose.yaml`; the cloud-specific infrastructure and setup are documented in the [infra guide](infra/README.md).

## How it fits together

- `web/` contains a build context for a container image. Add a directory with a `Dockerfile` for each additional image.
- `.github/workflows/push-image.yml` builds an image and pushes it to ECR, reusing the tag for a given image-directory revision.
- `.github/workflows/release.yml` runs for pushes to `main`. It builds or reuses the images, waits for approval in the GitHub `production` environment, then deploys `compose.yaml` to the instance.
- `compose.yaml` defines the services running on the instance. The release workflow supplies each service's image URI and release identifier through `.env`.
- `infra/` contains the Terraform modules for AWS resources and GitHub deployment settings. See [infra/README.md](infra/README.md) for prerequisites, first-time setup, day-to-day operations, and teardown.
- `justfile` provides shortcuts for common Terraform and instance tasks. Run `just` to list them.

## Start a project from this template

1. Create a repository from this template and configure its identity in `infra/project.auto.tfvars`. If reusing an existing checkout, follow the infra guide's notes about removing state and backend files that belong to another project.
2. Follow [First-time setup](infra/README.md#first-time-setup) to create the Terraform backend, configure AWS access, and provision the infrastructure and GitHub deployment settings.
3. Replace or extend `web/` with the application's Docker build context, then describe its services in `compose.yaml`.
4. Update the release workflow when adding images: add an image build job, include it in the deploy job's dependencies, and pass its image URI into the generated `.env`. The current workflow is wired for the single `web` image.
5. Push to `main` and approve the deployment through the repository's `production` environment.

## Adapting the template

The Compose file and container build contexts are the application-facing part of the template. The Terraform modules and GitHub Actions workflows form the current AWS deployment adapter. To use another cloud provider, replace or adapt the infrastructure, registry authentication, and remote deployment steps; the Compose service definitions can often stay the same if the target has a compatible Compose runtime.

For AWS-specific decisions and commands, use the [infrastructure guide](infra/README.md) rather than duplicating its operational details here.