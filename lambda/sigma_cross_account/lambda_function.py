import os
import json
import boto3
from botocore.exceptions import ClientError

ALLOWED_ACCOUNT_IDS = os.environ.get("ALLOWED_ACCOUNT_IDS", "").split(",")


def lambda_handler(event, context):
    target_account_id = event.get("target_account_id")
    target_role_name = event.get("target_role_name", "TerraformExecutionRole")
    session_name = event.get("session_name", "sigma-session")

    if not target_account_id:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "target_account_id is required"}),
        }

    if target_account_id not in ALLOWED_ACCOUNT_IDS:
        return {
            "statusCode": 403,
            "body": json.dumps({"error": f"Account {target_account_id} is not in the allowlist"}),
        }

    role_arn = f"arn:aws:iam::{target_account_id}:role/{target_role_name}"

    sts = boto3.client("sts")

    try:
        response = sts.assume_role(
            RoleArn=role_arn,
            RoleSessionName=session_name,
            DurationSeconds=3600,
        )

        creds = response["Credentials"]

        return {
            "statusCode": 200,
            "body": json.dumps({
                "access_key_id": creds["AccessKeyId"],
                "secret_access_key": creds["SecretAccessKey"],
                "session_token": creds["SessionToken"],
                "expiration": creds["Expiration"].isoformat(),
            }),
        }
    except ClientError as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)}),
        }
