#!/bin/bash
# ============================================================
# Book Review Pipeline - GCP Setup (Substack only)
# Run this locally with gcloud CLI installed and authenticated
# ============================================================

set -e

# ── CONFIG ── edit these before running ──────────────────────
PROJECT_ID="your-gcp-project-id"
REGION="us-central1"
ZONE="us-central1-a"
VM_NAME="book-review-pipeline"
BUCKET_NAME="${PROJECT_ID}-book-reviews"
SERVICE_ACCOUNT_NAME="book-review-sa"
# ─────────────────────────────────────────────────────────────

SA_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "🚀 Setting up Book Review Pipeline on GCP..."
gcloud config set project $PROJECT_ID

# Get project number (needed for Eventarc service account)
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
echo "📋 Project number: $PROJECT_NUMBER"

# Enable required APIs
echo "📡 Enabling GCP APIs..."
gcloud services enable \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  storage.googleapis.com \
  secretmanager.googleapis.com \
  logging.googleapis.com \
  compute.googleapis.com \
  eventarc.googleapis.com \
  run.googleapis.com \
  pubsub.googleapis.com

echo "⏳ Waiting 30s for APIs to propagate..."
sleep 30

# Create service account
echo "🔑 Creating service account..."
gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
  --display-name="Book Review Pipeline SA" \
  --project=$PROJECT_ID 2>/dev/null || echo "Service account already exists, continuing..."

# Grant all required roles to the pipeline service account
echo "🔐 Granting roles to pipeline service account..."
for ROLE in \
  roles/storage.objectAdmin \
  roles/secretmanager.secretAccessor \
  roles/logging.logWriter \
  roles/eventarc.eventReceiver \
  roles/run.invoker; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="$ROLE" \
    --condition=None 2>/dev/null || true
done

# Grant roles to the Eventarc service account
echo "🔐 Granting roles to Eventarc service account..."
EVENTARC_SA="service-${PROJECT_NUMBER}@gcp-sa-eventarc.iam.gserviceaccount.com"
for ROLE in \
  roles/eventarc.serviceAgent \
  roles/storage.admin; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${EVENTARC_SA}" \
    --role="$ROLE" \
    --condition=None 2>/dev/null || true
done

# Grant Cloud Storage service account pubsub publisher role
echo "🔐 Granting Cloud Storage service account Pub/Sub publisher role..."
STORAGE_SA=$(gcloud storage service-agent --project=$PROJECT_ID)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${STORAGE_SA}" \
  --role="roles/pubsub.publisher" \
  --condition=None 2>/dev/null || true

# Create GCS bucket using modern gcloud storage command
echo "🪣 Creating GCS bucket: gs://${BUCKET_NAME}/"
gcloud storage buckets create gs://${BUCKET_NAME} \
  --project=$PROJECT_ID \
  --location=$REGION 2>/dev/null || echo "Bucket already exists, continuing..."

# Grant Eventarc access to the bucket directly
echo "🔐 Granting Eventarc access to bucket..."
gcloud storage buckets add-iam-policy-binding gs://${BUCKET_NAME} \
  --member="serviceAccount:${EVENTARC_SA}" \
  --role="roles/storage.admin" 2>/dev/null || true

# Create the VM (e2-micro — cheapest, well within free tier)
echo "💻 Creating VM: $VM_NAME..."
gcloud compute instances create $VM_NAME \
  --project=$PROJECT_ID \
  --zone=$ZONE \
  --machine-type=e2-micro \
  --boot-disk-size=20GB \
  --boot-disk-type=pd-standard \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --service-account=$SA_EMAIL \
  --scopes=cloud-platform \
  --tags=book-review-pipeline \
  --metadata=startup-script='#!/bin/bash
    apt-get update -y
    apt-get install -y python3-pip python3-venv
    pip3 install google-cloud-storage google-cloud-secret-manager requests
  ' 2>/dev/null || echo "VM already exists, continuing..."

echo ""
echo "✅ Setup complete!"
echo ""
echo "Your bucket: gs://${BUCKET_NAME}/"
echo ""
echo "Next steps:"
echo "  1. Run: ./scripts/add-secrets.sh"
echo "  2. Run: ./scripts/deploy-function.sh"
echo "  3. Drop a review: gcloud storage cp my-review.md gs://${BUCKET_NAME}/incoming/"
