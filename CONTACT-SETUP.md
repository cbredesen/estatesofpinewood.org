# Contact Form — Deployment Guide

Serverless contact form for estatesofpinewood.org.
Architecture: Browser → CloudFront → API Gateway → Lambda → SES → inbox.

The form POSTs to `/api/contact` on the same CloudFront domain.
The destination email address is stored in SSM Parameter Store and is
never present in source code, Lambda config, or git history.

---

## Prerequisites

- AWS CLI configured with admin credentials
- All commands run from the repo root
- SES domain must be verified before the form can send mail

---

## Run order (first-time setup)

### Step 1 — Verify the sending domain in SES

```sh
./bin/07-verify-ses-domain.sh
```

Add the 3 DKIM CNAME records it prints to your DNS provider.
Re-run to confirm status. Verification typically takes a few minutes.

**SES sandbox note:** New accounts can only send to verified addresses.
After verification, request production access so the form can reach anyone:
https://console.aws.amazon.com/ses/home#/account

---

### Step 2 — Deploy Lambda + store destination email

```sh
CONTACT_EMAIL=you@youremail.com ./bin/08-create-contact-backend.sh
```

- Writes the email to SSM Parameter Store at `/eop/contact-email` (SecureString)
- Creates IAM role `eop-contact-role` with least-privilege SES + SSM + Logs permissions
- Packages and deploys the Python Lambda `eop-contact`

The `CONTACT_EMAIL` value is passed via shell environment only — never written
to any file. Subsequent runs (to update Lambda code) do not require the variable:

```sh
./bin/08-create-contact-backend.sh
```

---

### Step 3 — Create the API Gateway

```sh
./bin/09-create-contact-api.sh
```

- Creates an HTTP API named `eop-contact-api`
- Route: `POST /api/contact` → Lambda integration
- Throttling: 5 req/s sustained, burst 10
- CORS: allows `https://estatesofpinewood.org` and `www.`

---

### Step 4 — Wire API Gateway into CloudFront

```sh
./bin/10-add-api-to-cloudfront.sh
```

- Adds API Gateway as a second CloudFront origin
- Routes `/api/*` to that origin (CachingDisabled, no Host header forwarded)
- CloudFront deploys the change in ~1–2 minutes

Once live: `https://estatesofpinewood.org/api/contact`

---

## Updating the destination email (no redeploy required)

```sh
aws ssm put-parameter \
  --name /eop/contact-email \
  --value "new@youremail.com" \
  --type SecureString \
  --overwrite
```

The Lambda reads SSM on each cold start, so the change takes effect
automatically within minutes — no code change or deployment needed.

---

## Updating the Lambda function code

```sh
./bin/08-create-contact-backend.sh
```

(No `CONTACT_EMAIL` needed after first run.)

---

## What lives where

| Thing | Location |
|---|---|
| Destination email | SSM Parameter Store: `/eop/contact-email` (SecureString) |
| Sending address | `contact@estatesofpinewood.org` (hardcoded in Lambda; domain must be SES-verified) |
| Lambda function | `eop-contact` (us-east-1) |
| IAM role | `eop-contact-role` |
| API Gateway | `eop-contact-api` (HTTP API, us-east-1) |
| CloudFront behavior | `/api/*` → API Gateway origin |
| CloudFront Function | `eop-index-rewrite` (viewer-request, handles directory index rewrites) |

---

## Spam protection

- **Honeypot field:** a hidden `website` input that bots fill in; Lambda silently discards these submissions
- **API Gateway throttling:** 5 req/s rate limit, burst of 10
- **Input truncation:** name (100 chars), email (200), message (2000)

---

## Troubleshooting

**Form returns 403 or XML error**
- CloudFront hasn't finished deploying. Wait 2 minutes and retry.

**Form returns 500**
- Check Lambda logs in CloudWatch: `/aws/lambda/eop-contact`
- Common causes: SES not verified, SSM parameter missing, SES still in sandbox mode

**Emails not arriving**
- Confirm SES domain status: `./bin/07-verify-ses-domain.sh`
- If still in sandbox, verify the recipient address in the SES console,
  or request production access

**To tail Lambda logs:**
```sh
aws logs tail /aws/lambda/eop-contact --follow --region us-east-1
```
