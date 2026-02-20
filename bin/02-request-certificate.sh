#!/usr/bin/env bash
set -euo pipefail

# Requests an ACM certificate for the domain.
# MUST be in us-east-1 for CloudFront to use it.
# After running this script, you must validate the certificate via DNS
# (add the CNAME record shown in the output to your DNS provider).

DOMAIN="estatesofpinewood.org"
REGION="us-east-1"

echo "Requesting ACM certificate for ${DOMAIN} and www.${DOMAIN}..."
CERT_ARN=$(aws acm request-certificate \
  --domain-name "${DOMAIN}" \
  --subject-alternative-names "www.${DOMAIN}" \
  --validation-method DNS \
  --region "${REGION}" \
  --query 'CertificateArn' \
  --output text)

echo ""
echo "Certificate ARN: ${CERT_ARN}"
echo ""
echo "Waiting a few seconds for validation details to propagate..."
sleep 5

echo "DNS validation records needed:"
aws acm describe-certificate \
  --certificate-arn "${CERT_ARN}" \
  --region "${REGION}" \
  --query 'Certificate.DomainValidationOptions[].ResourceRecord' \
  --output table

echo ""
echo "Add the CNAME record(s) above to your DNS provider."
echo "Once validated, run 03-create-cloudfront.sh with this ARN:"
echo ""
echo "  CERT_ARN=${CERT_ARN} ./bin/03-create-cloudfront.sh"
