import json
import os
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError

TABLE_NAME = os.environ["TABLE_NAME"]
_table = boto3.resource("dynamodb").Table(TABLE_NAME)


# --------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------

def _cognito_sub(event):
    """Extract the authenticated user's Cognito sub from the JWT authorizer claims."""
    try:
        return event["requestContext"]["authorizer"]["jwt"]["claims"]["sub"]
    except (KeyError, TypeError):
        return None


def _json_default(o):
    if isinstance(o, Decimal):
        # DynamoDB returns numeric values as Decimal — coerce to float for JSON.
        return float(o)
    raise TypeError(f"not json serializable: {type(o)}")


def _respond(status, body=None):
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": "" if body is None else json.dumps(body, default=_json_default),
    }


# --------------------------------------------------------------------
# Handler
# --------------------------------------------------------------------

def lambda_handler(event, context):
    sub = _cognito_sub(event)
    if not sub:
        return _respond(401, {"error": "unauthenticated"})

    method = event.get("requestContext", {}).get("http", {}).get("method", "").upper()

    try:
        if method == "GET":
            return _get(sub)
        if method == "PUT":
            return _put(sub, event.get("body"))
        return _respond(405, {"error": "method_not_allowed"})
    except ClientError as e:
        return _respond(500, {"error": "dynamodb", "detail": str(e)})


def _get(sub):
    res = _table.get_item(Key={"userSub": sub})
    item = res.get("Item")
    if not item:
        return _respond(404, {"error": "not_found"})
    item.pop("userSub", None)
    return _respond(200, item)


def _put(sub, raw_body):
    if not raw_body:
        return _respond(400, {"error": "empty_body"})

    try:
        parsed = json.loads(raw_body)
    except json.JSONDecodeError:
        return _respond(400, {"error": "invalid_json"})

    if not isinstance(parsed, dict):
        return _respond(400, {"error": "body_must_be_object"})

    # DynamoDB does not accept native Python floats — convert via a JSON round-trip.
    item = json.loads(json.dumps(parsed), parse_float=Decimal)
    item["userSub"] = sub

    _table.put_item(Item=item)
    return _respond(200, {"ok": True})
