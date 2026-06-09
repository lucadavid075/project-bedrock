#!/usr/bin/env bash
set -euo pipefail

namespace="${APP_NAMESPACE:-retail-app}"
ingress_name="${INGRESS_NAME:-ui}"
aws_region="${AWS_REGION:-us-east-1}"
project_tag="karatu-2025-capstone"

echo "Waiting for ALB hostname on ingress ${namespace}/${ingress_name}..."
alb_host=""
for attempt in {1..60}; do
  alb_host="$(kubectl get ingress "$ingress_name" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [[ -n "$alb_host" ]]; then
    break
  fi

  echo "Attempt ${attempt}: ALB hostname not ready yet"
  sleep 10
done

if [[ -z "$alb_host" ]]; then
  echo "Ingress ${namespace}/${ingress_name} does not have an ALB hostname yet" >&2
  exit 1
fi

echo "ALB hostname: ${alb_host}"

alb_ip="$(
  python3 - "$alb_host" <<'PY'
import socket
import sys

hostname = sys.argv[1]
for info in socket.getaddrinfo(hostname, None, socket.AF_INET, socket.SOCK_STREAM):
    print(info[4][0])
    sys.exit(0)

sys.exit("no IPv4 address found")
PY
)"

if [[ -z "$alb_ip" ]]; then
  echo "Could not resolve an IPv4 address for ${alb_host}" >&2
  exit 1
fi

nipio_host="retail-store-${alb_ip//./-}.nip.io"
echo "Using nip.io host: ${nipio_host}"

set +e
existing_arn="$(
  aws acm list-certificates \
    --region "$aws_region" \
    --certificate-statuses ISSUED \
    --query "CertificateSummaryList[?DomainName=='${nipio_host}'].CertificateArn | [0]" \
    --output text 2>/tmp/acm-list-error.log
)"
list_exit_code=$?
set -e

if [[ "$list_exit_code" -ne 0 ]]; then
  echo "Could not list ACM certificates yet; continuing with import path"
  cat /tmp/acm-list-error.log || true
fi

if [[ -n "$existing_arn" && "$existing_arn" != "None" ]]; then
  certificate_arn="$existing_arn"
  echo "Reusing existing ACM certificate: ${certificate_arn}"
else
  cert_dir="$(mktemp -d)"
  trap 'rm -rf "$cert_dir"' EXIT

  openssl req \
    -x509 \
    -newkey rsa:2048 \
    -sha256 \
    -days 30 \
    -nodes \
    -subj "/CN=${nipio_host}" \
    -addext "subjectAltName=DNS:${nipio_host}" \
    -keyout "${cert_dir}/tls.key" \
    -out "${cert_dir}/tls.crt"

  echo "Importing self-signed certificate into ACM..."
  certificate_arn=""
  for attempt in {1..12}; do
    set +e
    certificate_arn="$(
      aws acm import-certificate \
        --region "$aws_region" \
        --certificate "fileb://${cert_dir}/tls.crt" \
        --private-key "fileb://${cert_dir}/tls.key" \
        --query CertificateArn \
        --output text 2>/tmp/acm-import-error.log
    )"
    exit_code=$?
    set -e

    if [[ "$exit_code" -eq 0 && -n "$certificate_arn" && "$certificate_arn" != "None" ]]; then
      break
    fi

    echo "ACM import attempt ${attempt} failed; retrying after IAM propagation"
    cat /tmp/acm-import-error.log || true
    sleep 10
  done

  if [[ -z "$certificate_arn" || "$certificate_arn" == "None" ]]; then
    echo "ACM certificate import failed" >&2
    exit 1
  fi

  aws acm add-tags-to-certificate \
    --region "$aws_region" \
    --certificate-arn "$certificate_arn" \
    --tags \
      "Key=Project,Value=${project_tag}" \
      "Key=ManagedBy,Value=github-actions-nipio-tls" \
      "Key=NipIoHost,Value=${nipio_host}" || true

  echo "Imported ACM certificate: ${certificate_arn}"
fi

if [[ -z "${GITHUB_ENV:-}" ]]; then
  echo "GITHUB_ENV is not set; this script is intended to run inside GitHub Actions" >&2
  exit 1
fi

{
  echo "TF_VAR_retail_store_host=${nipio_host}"
  echo "TF_VAR_alb_certificate_arn=${certificate_arn}"
  echo "NIPIO_TLS_HOST=${nipio_host}"
  echo "NIPIO_CERTIFICATE_ARN=${certificate_arn}"
  echo "NIPIO_ALB_HOST=${alb_host}"
  echo "NIPIO_ALB_IP=${alb_ip}"
} >> "$GITHUB_ENV"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## nip.io TLS fallback"
    echo
    echo "- ALB hostname: \`${alb_host}\`"
    echo "- Resolved IPv4: \`${alb_ip}\`"
    echo "- HTTPS URL: \`https://${nipio_host}\`"
    echo "- ACM certificate: \`${certificate_arn}\`"
    echo
    echo "This uses a self-signed certificate imported into ACM, so browsers will show a certificate warning."
  } >> "$GITHUB_STEP_SUMMARY"
fi
