# Project Bedrock

This is my AltSchool Africa Cloud Engineering capstone - a production-grade AWS EKS deployment for InnovateMart's retail microservices platform

The brief was to take an existing microservices application (the AWS Retail Store Sample App) and deploy it properly: managed databases instead of in-cluster containers, secure developer access, centralised logging, a CI/CD pipeline that actually works, and an event-driven serverless extension. Everything is provisioned with Terraform, deployed with Helm, and automated through GitHub Actions using OIDC - no long-lived credentials anywhere.

---

## What's in here

```
.github/workflows/terraform.yml   CI/CD pipeline - plan on PR, apply on merge, manual dispatch
bootstrap/                         One-time S3 state bucket setup
terraform/                         All AWS infrastructure as Terraform modules
helm/retail-store/                 Umbrella Helm chart with all 5 upstream sub-charts bundled
k8s/                               Reference manifests and RBAC definitions
lambda/                            Asset processor Lambda function
scripts/                           nip.io TLS bootstrap script
docs/                              Architecture diagram, runbook, OIDC setup guide
grading.json                       Required grading outputs (non-sensitive)
```

---

## Architecture

![Architecture diagram](docs/architecture.png)

The application runs on EKS v1.34 across two availability zones. Traffic enters through an ALB provisioned by the AWS Load Balancer Controller. The three stateful services — catalog (MySQL), orders (PostgreSQL), and cart (DynamoDB) — all use managed AWS databases instead of in-cluster containers. Credentials are stored in Secrets Manager and injected at deploy time. Logs ship to CloudWatch via the Observability addon and Fluent Bit.

The S3 bucket and Lambda function sit outside the cluster entirely — a file upload triggers the function, which logs the filename to CloudWatch.

More detail in [docs/architecture.md](docs/architecture.md).

---

## Live environment

| Resource | Value |
|---|---|
| AWS Region | `us-east-1` |
| EKS Cluster | `project-bedrock-cluster` |
| Application namespace | `retail-app` |
| Assets bucket | `bedrock-assets-alt-soe-025-4887` |
| Lambda function | `bedrock-asset-processor` |
| App URL | `http://k8s-retailap-ui-6039ab69e6-512914491.us-east-1.elb.amazonaws.com` |

The ALB hostname changes if the Ingress is recreated. Get the current one with:

```bash
kubectl get ingress -n retail-app \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
```

---

## CI/CD

The pipeline uses OIDC to assume an IAM role scoped to this repository. No AWS credentials are stored as GitHub secrets — just the role ARN.

**On pull request** — runs `terraform fmt`, `validate`, and `plan`. Posts the plan output as a PR comment so you can review what will change before merging.

**On merge to main** — runs `terraform apply` in two stages (infrastructure first, Kubernetes resources second), generates Helm values from live Terraform outputs, and deploys the chart.

**Manual dispatch** — supports `plan`, `apply`, and `destroy`. Apply also has an optional `enable_nipio_tls` toggle that imports a self-signed certificate into ACM and configures HTTPS on the ALB using a `nip.io` hostname.

Required GitHub secret:
```
AWS_ROLE_ARN = arn:aws:iam::<your-account-id>:role/project-bedrock-cluster-github-actions
```

Optional — set these to enable HTTPS with a real domain:
```
Repository variable: RETAIL_STORE_HOST = yourdomain.me
Repository secret:   ALB_CERTIFICATE_ARN = arn:aws:acm:us-east-1:...
```

OIDC provider setup is a one-time step documented in [docs/oidc-setup.md](docs/oidc-setup.md).

---

## Deploying from scratch

### Prerequisites
- AWS CLI v2 configured with admin credentials
- Terraform >= 1.10
- kubectl
- Helm >= 3.14

### First time only - bootstrap remote state

```bash
cd bootstrap
terraform init
terraform apply
```

This creates the S3 state bucket. Run it once, never again.

### Deploy everything

Push to main and the pipeline handles it. Or run locally:

```bash
cd terraform
terraform init
terraform apply
```

### Connect kubectl

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name project-bedrock-cluster
```

### Verify the application

```bash
kubectl get pods -n retail-app
kubectl get ingress -n retail-app
```

Expected pods: `ui`, `catalog`, `carts`, `checkout`, `checkout-redis`, `orders`, `orders-rabbitmq` — all Running.

---

## Helm deployment (Bonus)

The umbrella chart at `helm/retail-store/` bundles all five upstream sub-charts locally — no external registry needed.

Generate the runtime values file from live Terraform state:

```bash
cd terraform
terraform output -raw helm_values_rds > ../helm/retail-store/values-rds.yaml
cd ..
```

Deploy with a single command:

```bash
helm upgrade --install retail-store ./helm/retail-store \
  --namespace retail-app \
  --create-namespace \
  --wait \
  --timeout 10m \
  -f helm/retail-store/values-rds.yaml
```

---

## Verifying developer access

The `bedrock-dev-view` IAM user maps to the Kubernetes `view` ClusterRole via an EKS Access Entry. It can read but not modify cluster resources.

```bash
# Should return: yes
kubectl auth can-i get pods -n retail-app \
  --as=arn:aws:iam::757559216958:user/bedrock-dev-view

# Should return: no
kubectl auth can-i delete pod -n retail-app \
  --as=arn:aws:iam::757559216958:user/bedrock-dev-view
```

---

## Testing the Lambda trigger

Upload any file to the assets bucket using the `bedrock-dev-view` credentials:

```bash
echo "test" > test-image.txt
aws s3 cp test-image.txt \
  s3://bedrock-assets-alt-soe-025-4887/test-image.txt \
  --profile bedrock-dev
```

Check the Lambda logs:

```bash
aws logs tail /aws/lambda/bedrock-asset-processor \
  --region us-east-1 \
  --since 5m
```

Expected output: `Image received: test-image.txt`

---

## Retrieving grading credentials

These are sensitive — retrieve locally, never commit:

```bash
cd terraform
terraform output -raw bedrock_dev_access_key_id
terraform output -raw bedrock_dev_secret_access_key
terraform output -raw bedrock_dev_console_password
```

---

## Cleanup

**Always destroy locally** — the pipeline destroy is available but local is more reliable because your admin credentials are independent of the IAM role being deleted.

### Step 1 — Remove Helm releases first

This lets the Load Balancer Controller clean up the ALB it created. If you skip this, `terraform destroy` will fail with a VPC dependency error.

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name project-bedrock-cluster

helm uninstall retail-store -n retail-app || true
helm uninstall aws-load-balancer-controller -n kube-system || true
```

### Step 2 — Wait for the ALB to be deleted

```bash
echo "Waiting 90 seconds for ALB deletion..."
sleep 90

# Verify it's gone
aws elbv2 describe-load-balancers \
  --region us-east-1 \
  --query 'LoadBalancers[*].LoadBalancerName' \
  --output table
```

The table should be empty before continuing.

### Step 3 — Destroy infrastructure

```bash
cd terraform
terraform destroy -auto-approve
```

Takes about 20 minutes. RDS instances are the slowest to delete.

### What survives destroy (intentional)

These are not destroyed and should not be deleted manually:

| Resource | Why it survives |
|---|---|
| S3 state bucket `project-bedrock-tfstate-alt-soe-025-4887` | Keeps Terraform state for rebuild |
| GitHub OIDC provider in IAM | One allowed per account — recreating causes issues |

### Rebuilding after destroy

```bash
cd terraform
terraform init   # reconnects to the S3 state bucket
terraform apply  # rebuilds everything from scratch
```

---

## Cost reminder

This environment costs roughly $6/day while running - EKS control plane and NAT Gateway are the main drivers and can't be paused, only destroyed.