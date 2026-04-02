"""
Book Review Pipeline - Cloud Function (Substack only)
Triggered when a .md file is dropped into the GCS bucket.
Parses frontmatter and publishes to Substack.
"""

import functions_framework
import os
import re
import json
import requests
from google.cloud import storage, secretmanager
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PROJECT_ID = os.environ.get("GCP_PROJECT")
SUBSTACK_USER_ID = 350241999


# ── Secret Manager ────────────────────────────────────────────

def get_secret(secret_id):
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{PROJECT_ID}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")


# ── Markdown Parser ───────────────────────────────────────────

def parse_review(content: str) -> dict:
    """Parse frontmatter + body from the markdown file."""
    frontmatter = {}
    body = content

    fm_match = re.match(r'^---\n(.*?)\n---\n(.*)', content, re.DOTALL)
    if fm_match:
        raw_fm = fm_match.group(1)
        body = fm_match.group(2).strip()
        for line in raw_fm.splitlines():
            if ':' in line:
                key, _, val = line.partition(':')
                frontmatter[key.strip()] = val.strip().strip('"')

    return {
        "title": frontmatter.get("title", "Book Review"),
        "author": frontmatter.get("author", ""),
        "affiliate_link": frontmatter.get("affiliate_link", ""),
        "pull_quote": frontmatter.get("pull_quote", ""),
        "rating": frontmatter.get("rating", ""),
        "body": body,
    }


# ── ProseMirror Builder ───────────────────────────────────────

def text_to_prosemirror(text: str, affiliate_link: str, title: str) -> str:
    """Convert plain text to Substack's ProseMirror JSON format."""
    nodes = []

    for line in text.split("\n"):
        line = line.strip()
        if not line:
            continue
        elif line.startswith("## "):
            nodes.append({
                "type": "heading",
                "attrs": {"level": 2},
                "content": [{"type": "text", "text": line[3:]}]
            })
        elif line.startswith("# "):
            nodes.append({
                "type": "heading",
                "attrs": {"level": 1},
                "content": [{"type": "text", "text": line[2:]}]
            })
        else:
            nodes.append({
                "type": "paragraph",
                "attrs": {"textAlign": None},
                "content": [{"type": "text", "text": line}]
            })

    if affiliate_link:
        nodes.append({"type": "horizontalRule"})
        nodes.append({
            "type": "paragraph",
            "attrs": {"textAlign": None},
            "content": [
                {"type": "text", "text": "Grab it here: "},
                {
                    "type": "text",
                    "marks": [{"type": "link", "attrs": {"href": affiliate_link}}],
                    "text": title
                }
            ]
        })
        nodes.append({
            "type": "paragraph",
            "attrs": {"textAlign": None},
            "content": [
                {
                    "type": "text",
                    "marks": [{"type": "italic"}],
                    "text": "Disclosure: This post contains affiliate links. I may earn a small commission at no extra cost to you."
                }
            ]
        })

    return json.dumps({"type": "doc", "content": nodes})


# ── Substack ──────────────────────────────────────────────────

def post_to_substack(review: dict) -> dict:
    """Post review to Substack via their API."""
    cookie = get_secret("substack-token")
    publication_url = get_secret("substack-publication-url")
    publication_url = publication_url.replace("https://", "").replace("http://", "").strip().rstrip("/")

    headers = {
        "Content-Type": "application/json",
        "Cookie": cookie,
        "User-Agent": "Mozilla/5.0"
    }

    draft_body = text_to_prosemirror(
        review["body"],
        review.get("affiliate_link", ""),
        review["title"]
    )

    draft_payload = {
        "draft_title": f"Review: {review['title']} by {review['author']}",
        "draft_subtitle": review.get("pull_quote", ""),
        "draft_podcast_url": None,
        "draft_podcast_duration": None,
        "draft_body": draft_body,
        "section_chosen": False,
        "draft_section_id": None,
        "draft_bylines": [{"id": SUBSTACK_USER_ID, "is_guest": False}],
        "audience": "everyone",
        "type": "newsletter"
    }

    logger.info(f"Posting to: https://{publication_url}/api/v1/drafts")

    draft_resp = requests.post(
        f"https://{publication_url}/api/v1/drafts",
        headers=headers,
        json=draft_payload
    )

    if not draft_resp.ok:
        logger.error(f"Draft creation failed: {draft_resp.status_code} - {draft_resp.text}")
    draft_resp.raise_for_status()

    draft_id = draft_resp.json().get("id")
    logger.info(f"Draft created: {draft_id}")

    publish_resp = requests.post(
        f"https://{publication_url}/api/v1/drafts/{draft_id}/publish",
        headers=headers,
        json={"send": True, "share_automatically": False}
    )

    if not publish_resp.ok:
        logger.error(f"Publish failed: {publish_resp.status_code} - {publish_resp.text}")
    publish_resp.raise_for_status()

    post_url = publish_resp.json().get("published_byline_url", "")
    logger.info(f"Substack published: {post_url}")
    return {"success": True, "url": post_url}


# ── Main Entry Point ──────────────────────────────────────────

@functions_framework.cloud_event
def process_review(cloud_event):
    """Triggered by a GCS file upload. Reads the .md file and posts to Substack."""
    data = cloud_event.data
    bucket_name = data["bucket"]
    file_name = data["name"]

    if not file_name.startswith("incoming/") or not file_name.endswith(".md"):
        logger.info(f"Skipping {file_name} - not an incoming .md file")
        return

    logger.info(f"Processing: {file_name}")

    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(file_name)
    content = blob.download_as_text()

    review = parse_review(content)
    logger.info(f"Parsed: {review['title']} by {review['author']}")

    try:
        result = post_to_substack(review)
        logger.info(f"Done! Post live at: {result['url']}")
    except Exception as e:
        logger.error(f"Substack failed: {e}")
        raise

    processed_blob = bucket.blob(file_name.replace("incoming/", "processed/"))
    bucket.copy_blob(blob, bucket, processed_blob.name)
    blob.delete()
    logger.info(f"Moved to processed/")