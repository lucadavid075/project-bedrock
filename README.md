# Project Bedrock

Production-grade AWS EKS deployment for InnovateMart's retail microservices platform.

This repository contains Terraform infrastructure, a Helm-based application deployment, GitHub Actions CI/CD, EKS developer access, CloudWatch observability, and an S3-to-Lambda event-driven extension.

## Architecture

![Project Bedrock architecture](docs/architecture.png)

More detail is available in [docs/architecture.md](docs/architecture.md).

## Live Environment

| Item | Value |
|------|-------|
| AWS Region | `us-east-1` |
| EKS Cluster | `project-bedrock-cluster` |
| Application Namespace | `retail-app` |
| Assets Bucket | `bedrock-assets-alt-soe-025-4887` |
| Lambda Function | `bedrock-asset-processor` |
| Current Retail Store URL | `http://k8s-retailap-ui-6039ab69e6-512914491.us-east-1.elb.amazonaws.com` |

The ALB hostname can change if the Ingress is recreated. To retrieve the current URL:

```bash
kubectl get ingress -n retail-app \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
```

## Repository Layout

| Path | Purpose |
|------|---------|
| `.github/workflows/terraform.yml` | PR plan and merge-to-main apply workflow |
| `bootstrap/` | Remote state bootstrap configuration |
| `terraform/` | AWS infrastructure, EKS, RDS, IAM, Helm release, Lambda trigger |
| `helm/retail-store/` | Helm chart for the retail store application |
| `k8s/` | Reference Kubernetes namespace/RBAC/manifests |
| `lambda/` | Asset processor Lambda source |
| `docs/` | Architecture, OIDC setup, runbook, and submission notes |
| `grading.json` | Non-sensitive Terraform output subset for grading |

## CI/CD

GitHub Actions uses OIDC to assume the `project-bedrock-cluster-github-actions` IAM role. No long-lived AWS credentials are committed to this repository.

Workflow behavior:

- Pull requests to `main`: run `terraform fmt`, `terraform validate`, and `terraform plan`; post the plan as a PR comment.
- Pushes to `main`: run `terraform apply`, generate runtime Helm values, update kubeconfig, deploy the Helm chart, and verify pods/Ingress.
- Manual dispatch: supports `plan`, `apply`, `destroy`, and an optional `nip.io` TLS fallback for the apply path.

One-time OIDC setup is documented in [docs/oidc-setup.md](docs/oidc-setup.md).

Required GitHub secret:

```text
AWS_ROLE_ARN=arn:aws:iam::757559216958:role/project-bedrock-cluster-github-actions
```

Optional trusted HTTPS inputs:

```text
Repository variable: RETAIL_STORE_HOST=<your DNS name>
Repository secret:   ALB_CERTIFICATE_ARN=<ACM certificate ARN in us-east-1>
```

If those optional values are set, Terraform configures the ALB Ingress for HTTPS listeners and ACM certificate termination.

Free-tier `nip.io` HTTPS fallback:

1. Open the Terraform workflow manually.
2. Select `action=apply`.
3. Enable `enable_nipio_tls`.

The workflow deploys the HTTP ALB first, resolves one current ALB IPv4 address, builds a hostname like `retail-store-1-2-3-4.nip.io`, imports a 30-day self-signed certificate into ACM, and re-applies the Ingress with HTTPS listener annotations. This demonstrates TLS termination at the ALB through ACM without Route 53 or a paid domain, but browsers will warn because the certificate is self-signed.

## Local Verification

Configure kubectl:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name project-bedrock-cluster
```

Check the application:

```bash
kubectl get pods -n retail-app
kubectl get ingress -n retail-app
```

Expected pods include `ui`, `catalog`, `carts`, `checkout`, `checkout-redis`, `orders`, and `orders-rabbitmq`, all in `Running` state.

Verify developer RBAC:

```bash
kubectl auth can-i get pods -n retail-app \
  --as=arn:aws:iam::757559216958:user/bedrock-dev-view

kubectl auth can-i delete pod -n retail-app \
  --as=arn:aws:iam::757559216958:user/bedrock-dev-view
```

Expected:

```text
yes
no
```

## Lambda Trigger Test

Upload a test object:

```bash
echo "test image payload" > lambda-trigger-test.txt
aws s3 cp lambda-trigger-test.txt \
  s3://bedrock-assets-alt-soe-025-4887/lambda-trigger-test.txt \
  --region us-east-1
```

Check Lambda logs:

```bash
aws logs tail /aws/lambda/bedrock-asset-processor \
  --region us-east-1 \
  --since 10m
```

Expected log message:

```text
Image received: lambda-trigger-test.txt
```

## Grading Data

The committed `grading.json` intentionally contains only non-sensitive output values needed for grading. Do not commit raw Terraform output if it includes sensitive values such as the developer access key, secret key, console password, or rendered Helm values.

Required outputs are present:

- `cluster_endpoint`
- `cluster_name`
- `region`
- `vpc_id`
- `assets_bucket_name`

Developer credentials for the Google submission document should be retrieved locally, not committed:

```bash
terraform output -raw bedrock_dev_access_key_id
terraform output -raw bedrock_dev_secret_access_key
terraform output -raw bedrock_dev_console_password
```

## Submission

Use [docs/submission-template.md](docs/submission-template.md) as the copy/paste base for the Google Doc deliverable.

## Operations

Operational checks, Lambda trigger testing, and cleanup commands are documented in [docs/runbook.md](docs/runbook.md).

## Cost Reminder

EKS, NAT Gateway, RDS, and ALB resources incur ongoing AWS charges. Destroy the environment when grading is complete or when it is no longer needed.
