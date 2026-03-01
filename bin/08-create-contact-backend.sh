#!/usr/bin/env bash
set -euo pipefail

# Creates the IAM role and Lambda function for the contact form.
# The destination email is stored in SSM Parameter Store (SecureString)
# and read by Lambda at runtime — it never appears in code or git.
#
# Prerequisites:
#   - SES domain verified (07-verify-ses-domain.sh)
#
# First run — provide the destination email:
#   CONTACT_EMAIL=you@example.com ./bin/08-create-contact-backend.sh
#
# Subsequent runs (update Lambda code only):
#   ./bin/08-create-contact-backend.sh
#
# To change the destination email later (without redeploying):
#   aws ssm put-parameter --name /eop/contact-email \
#     --value "new@example.com" --type SecureString --overwrite

REGION="us-east-1"
FUNCTION_NAME="eop-contact"
ROLE_NAME="eop-contact-role"
SSM_PARAM="/eop/contact-email"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# --- SSM Parameter ---
PARAM_EXISTS=$(aws ssm get-parameter --name "${SSM_PARAM}" --region "${REGION}" \
  --query 'Parameter.Name' --output text 2>/dev/null || echo "")

if [[ -z "${PARAM_EXISTS}" ]]; then
  if [[ -z "${CONTACT_EMAIL:-}" ]]; then
    echo "Error: SSM parameter ${SSM_PARAM} not found."
    echo "Provide the destination email on first run:"
    echo "  CONTACT_EMAIL=you@example.com ./bin/08-create-contact-backend.sh"
    exit 1
  fi
  echo "Storing destination email in SSM Parameter Store..."
  aws ssm put-parameter \
    --name "${SSM_PARAM}" \
    --value "${CONTACT_EMAIL}" \
    --type SecureString \
    --region "${REGION}" > /dev/null
  echo "  Stored at: ${SSM_PARAM} (SecureString)"
else
  echo "SSM parameter ${SSM_PARAM} already exists — skipping."
fi

# --- IAM Role ---
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

if ! aws iam get-role --role-name "${ROLE_NAME}" > /dev/null 2>&1; then
  echo "Creating IAM role ${ROLE_NAME}..."
  aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "lambda.amazonaws.com"},
        "Action": "sts:AssumeRole"
      }]
    }' > /dev/null
fi

echo "Attaching policy to ${ROLE_NAME}..."
aws iam put-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name "eop-contact-policy" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Sid\": \"Logs\",
        \"Effect\": \"Allow\",
        \"Action\": [
          \"logs:CreateLogGroup\",
          \"logs:CreateLogStream\",
          \"logs:PutLogEvents\"
        ],
        \"Resource\": \"arn:aws:logs:*:*:*\"
      },
      {
        \"Sid\": \"SES\",
        \"Effect\": \"Allow\",
        \"Action\": \"ses:SendEmail\",
        \"Resource\": \"*\"
      },
      {
        \"Sid\": \"SSM\",
        \"Effect\": \"Allow\",
        \"Action\": \"ssm:GetParameter\",
        \"Resource\": \"arn:aws:ssm:${REGION}:${ACCOUNT_ID}:parameter/eop/contact-email\"
      }
    ]
  }"

# --- Lambda function code ---
WORKDIR=$(mktemp -d)
trap "rm -rf ${WORKDIR}" EXIT

cat > "${WORKDIR}/lambda_function.py" <<'PYEOF'
import json
import os
import re
import boto3

# Read destination email from SSM at cold start.
# It is never stored in environment variables, Lambda config, or source code.
_ssm = boto3.client('ssm')
RECIPIENT = _ssm.get_parameter(
    Name='/eop/contact-email',
    WithDecryption=True
)['Parameter']['Value']

SENDER = 'contact@estatesofpinewood.org'
_ses = boto3.client('ses')


def handler(event, context):
    try:
        body = json.loads(event.get('body') or '{}')
    except (json.JSONDecodeError, TypeError):
        return _resp(400, {'error': 'Invalid request'})

    # Honeypot: legitimate users leave this blank; bots fill it in
    if body.get('website'):
        return _resp(200, {'ok': True})

    name    = str(body.get('name',    '')).strip()[:100]
    email   = str(body.get('email',   '')).strip()[:200]
    message = str(body.get('message', '')).strip()[:2000]

    if not name or not email or not message:
        return _resp(400, {'error': 'All fields are required.'})

    if not re.fullmatch(r'[^@\s]+@[^@\s]+\.[^@\s]+', email):
        return _resp(400, {'error': 'Invalid email address.'})

    _ses.send_email(
        Source=SENDER,
        Destination={'ToAddresses': [RECIPIENT]},
        Message={
            'Subject': {'Data': f'EOP Contact: {name}'},
            'Body': {
                'Text': {
                    'Data': (
                        f"Name:    {name}\n"
                        f"Email:   {email}\n\n"
                        f"Message:\n{message}"
                    )
                }
            }
        },
        ReplyToAddresses=[email],
    )

    return _resp(200, {'ok': True})


def _resp(status, body):
    return {
        'statusCode': status,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps(body),
    }
PYEOF

(cd "${WORKDIR}" && zip -q contact.zip lambda_function.py)

# --- Deploy Lambda ---
FUNCTION_EXISTS=$(aws lambda get-function --function-name "${FUNCTION_NAME}" \
  --region "${REGION}" --query 'Configuration.FunctionName' --output text 2>/dev/null || echo "")

if [[ -z "${FUNCTION_EXISTS}" ]]; then
  echo "Creating Lambda function ${FUNCTION_NAME}..."
  # IAM role propagation can take a few seconds
  sleep 10
  aws lambda create-function \
    --function-name "${FUNCTION_NAME}" \
    --runtime python3.12 \
    --handler lambda_function.handler \
    --role "${ROLE_ARN}" \
    --zip-file "fileb://${WORKDIR}/contact.zip" \
    --timeout 10 \
    --memory-size 128 \
    --region "${REGION}" > /dev/null
else
  echo "Updating Lambda function code..."
  aws lambda update-function-code \
    --function-name "${FUNCTION_NAME}" \
    --zip-file "fileb://${WORKDIR}/contact.zip" \
    --region "${REGION}" > /dev/null
fi

LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${FUNCTION_NAME}"

echo ""
echo "Contact backend ready!"
echo "  Lambda: ${LAMBDA_ARN}"
echo ""
echo "Next: run 09-create-contact-api.sh"
