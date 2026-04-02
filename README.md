# 📚 Book Review Pipeline — Substack Edition

Drop a markdown file into a GCS bucket → auto-publishes to your Substack. That's it.

## How It Works

```
You write review (.md file)
        ↓
gsutil cp review.md gs://YOUR_BUCKET/incoming/
        ↓
Cloud Function triggers automatically
        ↓
Parses your review + frontmatter
        ↓
Posts to Substack (draft → publish)
        ↓
File moved to /processed/
```

## Setup (one time, ~10 minutes)

### Prerequisites
- `gcloud` CLI installed → https://cloud.google.com/sdk
- GCP project with billing enabled
- Substack publication set up

### Step 1 — Edit your Project ID
Open each file in `scripts/` and replace `your-gcp-project-id` with your real GCP project ID.
(Find it in the GCP Console header or run `gcloud projects list`)

### Step 2 — Run the scripts in order
```bash
chmod +x scripts/*.sh

./scripts/setup-vm.sh        # Creates VM, bucket, IAM (~2 min)
./scripts/add-secrets.sh     # Stores your Substack token securely
./scripts/deploy-function.sh # Deploys the Cloud Function
```

### Step 3 — Get your Substack token
1. Go to substack.com and log in
2. Open DevTools → F12 (Chrome/Firefox)
3. Go to **Application** tab → **Cookies** → **substack.com**
4. Find the cookie named `substack.sid`
5. Copy the value — paste it when `add-secrets.sh` prompts you

## Posting a Review

1. Write your review using the template in `templates/example-review.md`
2. Save it as `my-book-title.md`
3. Upload it:
```bash
gsutil cp my-book-title.md gs://YOUR_BUCKET_NAME/incoming/
```
The Cloud Function fires within seconds. Your post goes live on Substack automatically.

## Review File Format

```markdown
---
title: "The Name of the Wind"
author: "Patrick Rothfuss"
affiliate_link: https://amzn.to/YOURTAG
pull_quote: "The best fantasy debut in a decade"
rating: ⭐⭐⭐⭐⭐
---

Your review body here...
```

| Field | Required | Description |
|-------|----------|-------------|
| `title` | ✅ | Book title |
| `author` | ✅ | Author name |
| `affiliate_link` | ✅ | Amazon Associates URL |
| `pull_quote` | Optional | Subtitle on Substack post |
| `rating` | Optional | Star rating |

## Monitoring

```bash
# View live logs
gcloud functions logs read process-book-review --region=us-central1 --limit=50
```

Or in the GCP Console → Cloud Functions → process-book-review → Logs

## Estimated Cost

| Service | Monthly Cost |
|---------|-------------|
| Cloud Function (1–4 invocations/week) | $0.00 (free tier) |
| GCS Storage (markdown files) | ~$0.01 |
| e2-micro VM | $0–7 (free tier eligible) |
| Secret Manager | ~$0.06 |
| **Total** | **< $8/month** |

Your $250 credit covers this for 30+ months.

## Adding More Platforms Later

When you're ready to add X or Reddit, the `main.py` Cloud Function
is already structured to add new posting functions cleanly.
Just add a new `post_to_x()` function and call it after Substack.
