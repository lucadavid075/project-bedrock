"""
bedrock-asset-processor
Triggered by S3 ObjectCreated events on the assets bucket.
Logs the filename of each uploaded object to CloudWatch.
"""

import json
import logging
import urllib.parse

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event: dict, context) -> dict:
    """Entry point for S3 event notifications."""
    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        logger.info("Image received: %s (bucket: %s)", key, bucket)

    return {
        "statusCode": 200,
        "body": json.dumps({"message": "Processed successfully"}),
    }
