# GitHub Actions OIDC Setup

GitHub Actions deploys this project by assuming the AWS IAM role:

```text
arn:aws:iam::757559216958:role/project-bedrock-cluster-github-actions
```

The workflow uses OIDC, so no long-lived AWS access keys are stored in GitHub.

## One-Time AWS OIDC Provider

The Terraform configuration expects the AWS account to already have the GitHub Actions OIDC provider:

```text
https://token.actions.githubusercontent.com
```

Check whether it exists:

```bash
aws iam list-open-id-connect-providers \
  --query 'OpenIDConnectProviderList[].Arn' \
  --output text
```

If missing, create it once:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

## Bootstrap the GitHub Actions Role

The role must exist before the GitHub workflow can assume it. From a local machine authenticated as an AWS admin:

```bash
cd terraform
terraform init
terraform apply \
  -target=aws_iam_role.github_actions \
  -target=aws_iam_policy.github_actions_cicd_1 \
  -target=aws_iam_policy.github_actions_cicd_2 \
  -target=aws_iam_role_policy_attachment.github_actions_cicd_1 \
  -target=aws_iam_role_policy_attachment.github_actions_cicd_2
```

After the EKS cluster exists, bootstrap EKS cluster access for the CI role:

```bash
terraform apply \
  -target=aws_eks_access_entry.github_actions \
  -target=aws_eks_access_policy_association.github_actions_admin
```

Targeted applies are only for bootstrapping/recovery. Routine changes should go through a normal PR and merge-to-main workflow.

## GitHub Secret

Add this repository secret:

```text
AWS_ROLE_ARN=arn:aws:iam::757559216958:role/project-bedrock-cluster-github-actions
```

Path:

```text
GitHub repository -> Settings -> Secrets and variables -> Actions -> New repository secret
```

## Optional HTTPS Inputs

For trusted HTTPS with a domain you control, add:

```text
Repository variable: RETAIL_STORE_HOST=<your DNS name>
Repository secret:   ALB_CERTIFICATE_ARN=<ACM certificate ARN in us-east-1>
```

The ACM certificate must already be issued or imported in `us-east-1`.

For the no-cost `nip.io` fallback, run the Terraform workflow manually with `action=apply` and `enable_nipio_tls=true`. The workflow imports a self-signed `nip.io` certificate into ACM and re-applies the ALB Ingress annotations.

## Verification

Open a pull request. The workflow should:

1. Authenticate to AWS through OIDC.
2. Run `terraform init`.
3. Run `terraform fmt`, `terraform validate`, and `terraform plan`.
4. Post the plan output as a PR comment.

After merging to `main`, the workflow would apply Terraform and deploy the Helm release.
