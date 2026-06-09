# Operations Runbook

Use this runbook to verify the deployed environment before grading.

## Configure kubectl

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name project-bedrock-cluster
```

## Verify Application Health

```bash
kubectl get pods -n retail-app -o wide
kubectl get ingress -n retail-app -o wide
```

All application pods should be `Running` and ready.

Get the current application URL:

```bash
ALB_HOST=$(kubectl get ingress -n retail-app \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')

echo "http://${ALB_HOST}"
```

On PowerShell:

```powershell
$ALB_HOST = kubectl get ingress -n retail-app -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
"http://$ALB_HOST"
```

## Enable Free-Tier nip.io TLS

Use this path only when you do not own a domain and do not want Route 53. In GitHub Actions, run the Terraform workflow manually with:

```text
action=apply
enable_nipio_tls=true
```

The workflow will:

- Deploy the ALB-backed HTTP Ingress.
- Resolve one current ALB IPv4 address.
- Create a `retail-store-<ip>.nip.io` hostname.
- Import a 30-day self-signed certificate into ACM.
- Re-apply the Ingress with HTTPS listener, certificate, and SSL redirect annotations.

The workflow summary prints the HTTPS URL. Verify it with:

```bash
curl -k -I https://<printed-nipio-host>
```

The `-k` flag is required because the fallback certificate is self-signed. If the ALB is recreated or AWS changes the selected ALB IP, rerun the manual workflow to generate a fresh `nip.io` host and certificate.

## Verify Developer Access

The EKS access entry maps the IAM user to the Kubernetes username:

```text
arn:aws:iam::757559216958:user/bedrock-dev-view
```

Expected read access:

```bash
kubectl auth can-i get pods -n retail-app \
  --as=arn:aws:iam::757559216958:user/bedrock-dev-view
```

Expected denial for mutation:

```bash
kubectl auth can-i delete pod -n retail-app \
  --as=arn:aws:iam::757559216958:user/bedrock-dev-view
```

Expected output:

```text
yes
no
```

## Verify CloudWatch Logs

```bash
aws logs describe-log-groups \
  --region us-east-1 \
  --log-group-name-prefix /aws/eks/project-bedrock-cluster

aws logs describe-log-groups \
  --region us-east-1 \
  --log-group-name-prefix /aws/containerinsights/project-bedrock-cluster
```

## Trigger Lambda from S3

Create and upload a test object:

```bash
echo "test image payload" > lambda-trigger-test.txt

aws s3 cp lambda-trigger-test.txt \
  s3://bedrock-assets-alt-soe-025-4887/lambda-trigger-test.txt \
  --region us-east-1
```

PowerShell:

```powershell
"test image payload" | Set-Content -Path lambda-trigger-test.txt

aws s3 cp lambda-trigger-test.txt `
  s3://bedrock-assets-alt-soe-025-4887/lambda-trigger-test.txt `
  --region us-east-1
```

Check Lambda logs:

```bash
aws logs tail /aws/lambda/bedrock-asset-processor \
  --region us-east-1 \
  --since 10m
```

Expected message:

```text
Image received: lambda-trigger-test.txt
```

## Retrieve Grading Credentials

Run from the Terraform root:

```bash
terraform output -raw bedrock_dev_access_key_id
terraform output -raw bedrock_dev_secret_access_key
terraform output -raw bedrock_dev_console_password
```

Do not commit these values. Paste them only into the private Google Doc submission.

## Cleanup After Grading

Use the manual workflow dispatch with `destroy`, or run locally:

```bash
cd terraform
terraform destroy -auto-approve -input=false
```

Before destroy, remove Helm-created load balancers if needed:

```bash
helm uninstall retail-store -n retail-app || true
helm uninstall aws-load-balancer-controller -n kube-system || true
```
