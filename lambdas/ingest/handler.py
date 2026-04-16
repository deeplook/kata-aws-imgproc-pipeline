import base64
import json
import os
import urllib.parse
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth


_OS_CLIENT = None
INDEX_NAME = "photos"


def _get_opensearch_client():
    global _OS_CLIENT
    if _OS_CLIENT is None:
        region = os.environ["AWS_REGION_NAME"]
        credentials = boto3.Session().get_credentials()
        awsauth = AWS4Auth(
            credentials.access_key,
            credentials.secret_key,
            region,
            "aoss",
            session_token=credentials.token,
        )
        endpoint = os.environ["OPENSEARCH_ENDPOINT"].removeprefix("https://")
        _OS_CLIENT = OpenSearch(
            hosts=[{"host": endpoint, "port": 443}],
            http_auth=awsauth,
            use_ssl=True,
            verify_certs=True,
            connection_class=RequestsHttpConnection,
        )
    return _OS_CLIENT


def _ensure_index(client):
    if client.indices.exists(index=INDEX_NAME):
        return
    try:
        client.indices.create(index=INDEX_NAME, body={
            "settings": {"index": {"knn": True}},
            "mappings": {
                "properties": {
                    "image_key": {"type": "keyword"},
                    "labels":    {"type": "keyword"},
                    "embedding": {
                        "type": "knn_vector",
                        "dimension": 1024,
                        "method": {
                            "name":       "hnsw",
                            "space_type": "cosinesimil",
                            "engine":     "nmslib",
                        },
                    },
                }
            },
        })
        print(f"OpenSearch: index '{INDEX_NAME}' created")
    except Exception as e:
        # Concurrent Lambda invocations may both attempt index creation;
        # swallow resource_already_exists_exception so both can proceed to index.
        if "resource_already_exists_exception" not in str(e).lower():
            raise


def lambda_handler(event, context):
    print("Ingest Lambda invoked")

    if not event.get("Records"):
        return {"statusCode": 400, "body": json.dumps({"message": "Invalid event: no Records"})}

    try:
        bucket_name = event["Records"][0]["s3"]["bucket"]["name"]
        raw_key = event["Records"][0]["s3"]["object"]["key"]
        object_key = urllib.parse.unquote_plus(raw_key, encoding="utf-8")
        print(f"Processing: s3://{bucket_name}/{object_key}")

        # Stage 2: Rekognition
        rekognition = boto3.client("rekognition")
        response = rekognition.detect_labels(
            Image={"S3Object": {"Bucket": bucket_name, "Name": object_key}},
            MaxLabels=10,
            MinConfidence=75,
        )
        labels = response["Labels"]
        print(f"Rekognition: {len(labels)} labels detected")
        for label in labels:
            print(f"  - {label['Name']}: {label['Confidence']:.2f}%")
        label_names = [label["Name"] for label in labels]

        # Stage 3: DynamoDB
        dynamodb = boto3.resource("dynamodb")
        table = dynamodb.Table(os.environ["TABLE_NAME"])
        table.put_item(Item={
            "image_key": object_key,
            "labels": label_names,
            "upload_timestamp": datetime.now(timezone.utc).isoformat(),
        })
        print("DynamoDB: record written")

        # Stage 4: Bedrock embeddings
        s3_client = boto3.client("s3")
        img_bytes = s3_client.get_object(Bucket=bucket_name, Key=object_key)["Body"].read()
        img_b64 = base64.b64encode(img_bytes).decode("utf-8")

        bedrock = boto3.client("bedrock-runtime")
        response = bedrock.invoke_model(
            modelId="amazon.titan-embed-image-v1",
            body=json.dumps({"inputImage": img_b64}),
            contentType="application/json",
            accept="application/json",
        )
        embedding = json.loads(response["body"].read())["embedding"]
        print(f"embedding: {len(embedding)} dimensions")

        embedding_decimal = [Decimal(str(v)) for v in embedding]
        table.update_item(
            Key={"image_key": object_key},
            UpdateExpression="SET embedding = :e",
            ExpressionAttributeValues={":e": embedding_decimal},
        )

        # Stage 5: OpenSearch indexing
        os_client = _get_opensearch_client()
        _ensure_index(os_client)
        os_client.index(index=INDEX_NAME, body={
            "image_key": object_key,
            "labels":    label_names,
            "embedding": embedding,
        })
        print("OpenSearch: indexed")

        print(json.dumps({
            "key": object_key,
            "labels": label_names,
            "dimensions": len(embedding),
            "indexed": True,
        }))
        return {"statusCode": 200, "body": json.dumps({"key": object_key, "labels": label_names})}

    except ClientError as e:
        code = e.response["Error"]["Code"]
        print(f"AWS error [{code}]: {e}")
        return {"statusCode": 500, "body": json.dumps({"message": f"AWS error: {code}"})}
    except Exception as e:
        print(f"Unexpected error: {e}")
        return {"statusCode": 500, "body": json.dumps({"message": "Internal error"})}
