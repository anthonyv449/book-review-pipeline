#!/bin/bash
# ============================================================
# Deploy the Book Review Cloud Function
# Run after setup-vm.sh and add-secrets.sh
# ============================================================

set -e

PROJECT_ID="project-f40bc29e-c7cd-4098-b50"
BUCKET_NAME="${PROJECT_ID}-book-reviews"
REGION="us-central1"
FUNCTION_NAME="process-book-review"
SA_EMAIL="book-review-sa@${PROJECT_ID}.iam.gserviceaccount.com"

echo "🚀 Deploying Book Review Cloud Function..."

# Verify bucket exists before deploying
echo "🪣 Verifying bucket exists..."
gcloud storage ls gs://${BUCKET_NAME} > /dev/null 2>&1 || {
  echo "❌ Bucket gs://${BUCKET_NAME} not found. Run setup-vm.sh first."
  exit 1
}
echo "✅ Bucket found"

# Verify secrets exist
echo "🔐 Verifying secrets exist..."
gcloud secrets describe substack-token --project=$PROJECT_ID > /dev/null 2>&1 || {
  echo "❌ Secret 'substack-token' not found. Run add-secrets.sh first."
  exit 1
}
gcloud secrets describe substack-publication-url --project=$PROJECT_ID > /dev/null 2>&1 || {
  echo "❌ Secret 'substack-publication-url' not found. Run add-secrets.sh first."
  exit 1
}
echo "✅ Secrets found"

# Deploy
gcloud functions deploy $FUNCTION_NAME \
  --gen2 \
  --runtime=python311 \
  --region=$REGION \
  --source=./cloud-function \
  --entry-point=process_review \
  --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
  --trigger-event-filters="bucket=${BUCKET_NAME}" \
  --service-account=$SA_EMAIL \
  --set-env-vars="GCP_PROJECT=${PROJECT_ID}" \
  --memory=256Mi \
  --timeout=120s \
  --project=$PROJECT_ID

echo ""
echo "✅ Cloud Function deployed!"
echo ""
echo "To post a review:"
echo "  gcloud storage cp your-review.md gs://${BUCKET_NAME}/incoming/"
echo ""
echo "Monitor logs:"
echo "  gcloud functions logs read $FUNCTION_NAME --region=$REGION --limit=50"
