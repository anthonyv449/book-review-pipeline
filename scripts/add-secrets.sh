#!/bin/bash
# ============================================================
# Add Substack secrets to GCP Secret Manager
# Run after setup-vm.sh
# ============================================================

PROJECT_ID="your-gcp-project-id"

echo "🔐 Adding Substack secrets to GCP Secret Manager..."
echo ""

add_secret() {
  local SECRET_NAME=$1
  local PROMPT=$2

  echo "── $PROMPT ──"
  read -s -p "Paste value: " SECRET_VALUE
  echo ""

  echo -n "$SECRET_VALUE" | gcloud secrets create $SECRET_NAME \
    --data-file=- \
    --project=$PROJECT_ID 2>/dev/null || \
  echo -n "$SECRET_VALUE" | gcloud secrets versions add $SECRET_NAME \
    --data-file=- \
    --project=$PROJECT_ID

  echo "✅ $SECRET_NAME saved"
  echo ""
}

# Substack session token
# How to find it:
#   1. Go to substack.com and log in
#   2. Open DevTools (F12) → Application → Cookies → substack.com
#   3. Copy the value of the cookie named: substack.sid
add_secret "substack-token" "Substack session token (substack.sid cookie value)"

# Your Substack publication URL — just the subdomain
# e.g. if your Substack is at myblog.substack.com, enter: myblog.substack.com
add_secret "substack-publication-url" "Substack publication URL (e.g. myblog.substack.com)"

# Amazon Associates tag (optional — used in affiliate links)
# e.g. yourtag-20
add_secret "amazon-associates-tag" "Amazon Associates tracking tag (e.g. yourtag-20)"

echo "🎉 All secrets stored! Your keys are never stored in code or on disk."
