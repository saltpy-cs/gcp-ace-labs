import functions_framework
import base64
import json
import logging


@functions_framework.cloud_event
def handle_event(cloud_event):
    """Pub/Sub Cloud Function: logs incoming event data."""
    message_data = base64.b64decode(
        cloud_event.data["message"]["data"]
    ).decode("utf-8")

    try:
        payload = json.loads(message_data)
        logging.info(f"Received structured event: {json.dumps(payload, indent=2)}")
        print(f"Processed event: type={payload.get('type', 'unknown')}, "
              f"value={payload.get('value', 'N/A')}")
    except json.JSONDecodeError:
        logging.info(f"Received plain text event: {message_data}")
        print(f"Processed plain message: {message_data}")
