#!/usr/bin/env python3
"""Publish the repository's recommendation catalog to the existing R2 object."""

import configparser
import json
import sys
from pathlib import Path

import boto3


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "xxmac.json"
RCLONE_CONFIG = Path.home() / ".config/rclone/rclone.conf"
REMOTE = "cfr2"
BUCKET = "blog"
KEY = "xxmac/xxmac.json"


def read_catalog() -> bytes:
    body = SOURCE.read_bytes()
    document = json.loads(body)
    categories = document.get("categories")
    if not isinstance(categories, list):
        raise ValueError("xxmac.json must contain a categories array")
    category_ids = set()
    for category in categories:
        category_id = category["id"]
        if category_id in category_ids:
            raise ValueError(f"Duplicate category id: {category_id}")
        category_ids.add(category_id)
        if not isinstance(category["items"], list):
            raise ValueError(f"Category {category_id} must contain an items array")
        item_ids = set()
        for item in category["items"]:
            item_id = item["id"]
            if item_id in item_ids:
                raise ValueError(f"Duplicate item id in {category_id}: {item_id}")
            item_ids.add(item_id)
            if not item["title"] or not item["url"].startswith("https://"):
                raise ValueError(f"Item {item_id} needs a title and HTTPS URL")
    return body


def main() -> None:
    body = read_catalog()
    config = configparser.ConfigParser()
    if not config.read(RCLONE_CONFIG) or REMOTE not in config:
        raise RuntimeError(f"Missing [{REMOTE}] in {RCLONE_CONFIG}")
    remote = config[REMOTE]
    client = boto3.client(
        "s3",
        endpoint_url=remote["endpoint"],
        aws_access_key_id=remote["access_key_id"],
        aws_secret_access_key=remote["secret_access_key"],
        region_name=remote.get("region", "auto"),
    )
    client.put_object(
        Bucket=BUCKET,
        Key=KEY,
        Body=body,
        ContentType="application/json; charset=utf-8",
    )

    published = client.get_object(Bucket=BUCKET, Key=KEY)["Body"].read()
    if published != body:
        raise RuntimeError("R2 upload succeeded, but the stored object does not match xxmac.json")
    print(f"Synced {SOURCE.name} to {BUCKET}/{KEY} and verified the R2 object")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        print(f"syncjson: {error}", file=sys.stderr)
        sys.exit(1)
