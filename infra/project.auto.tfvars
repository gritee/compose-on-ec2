# What this project is and where it lives. Loaded by every module in infra/ (bootstrap/
# and account/ link to this file). A copy of this repo starts by editing these values.
# The placeholders are invalid on purpose: Terraform stops until they're filled in.
account_id        = "<aws-account-id>" # 12 digits
region            = "us-east-1"
name              = "<name>"         # resource name prefix: lowercase letters, digits, hyphens
github_repository = "<owner>/<repo>" # this repo
