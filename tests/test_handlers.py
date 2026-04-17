"""
Minimal handler tests using moto for AWS service mocks.
OpenSearch is patched at the client level (no moto support).
Bedrock is patched at the client level (Titan Embed Image not in moto).
"""
import importlib.util
import json
import sys
from unittest.mock import MagicMock, patch

import boto3
import pytest
from moto import mock_aws


# ---------------------------------------------------------------------------
# Load both Lambda handlers under distinct module names to avoid collision
# ---------------------------------------------------------------------------

def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


ingest = _load("ingest", "lambdas/ingest/handler.py")
search = _load("search", "lambdas/search/handler.py")

# ---------------------------------------------------------------------------
# Shared constants
# ---------------------------------------------------------------------------

REGION = "us-east-1"
BUCKET = "test-bucket"
TABLE = "test-table"
IMAGE_KEY = "photo.jpg"
FAKE_EMBEDDING = [0.1] * 1024

S3_EVENT = {
    "Records": [{
        "s3": {
            "bucket": {"name": BUCKET},
            "object": {"key": IMAGE_KEY},
        }
    }]
}

# ---------------------------------------------------------------------------
# Shared fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def aws_credentials(monkeypatch):
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", REGION)
    monkeypatch.setenv("AWS_REGION_NAME", REGION)


@pytest.fixture(autouse=True)
def handler_env(monkeypatch):
    monkeypatch.setenv("TABLE_NAME", TABLE)
    monkeypatch.setenv("OPENSEARCH_ENDPOINT", "https://fake.us-east-1.aoss.amazonaws.com")
    monkeypatch.setenv("COLLECTION_NAME", "test-collection")


@pytest.fixture(autouse=True)
def reset_handler_state():
    """Clear module-level cached clients between tests."""
    ingest._OS_CLIENT = None
    search._OS_CLIENT = None
    search._BEDROCK_CLIENT = None
    yield
    ingest._OS_CLIENT = None
    search._OS_CLIENT = None
    search._BEDROCK_CLIENT = None


# ---------------------------------------------------------------------------
# Ingest handler
# ---------------------------------------------------------------------------


def test_ingest_missing_records_returns_400():
    response = ingest.lambda_handler({}, None)
    assert response["statusCode"] == 400
    assert "Invalid event" in json.loads(response["body"])["message"]


@mock_aws
def test_ingest_writes_dynamodb_record():
    # Set up S3 with a fake image
    s3 = boto3.client("s3", region_name=REGION)
    s3.create_bucket(Bucket=BUCKET)
    s3.put_object(Bucket=BUCKET, Key=IMAGE_KEY, Body=b"\xff\xd8\xff")

    # Set up DynamoDB table
    ddb = boto3.resource("dynamodb", region_name=REGION)
    table = ddb.create_table(
        TableName=TABLE,
        KeySchema=[{"AttributeName": "image_key", "KeyType": "HASH"}],
        AttributeDefinitions=[{"AttributeName": "image_key", "AttributeType": "S"}],
        BillingMode="PAY_PER_REQUEST",
    )

    # Bedrock mock — Titan Embed Image not modelled by moto
    fake_body = MagicMock()
    fake_body.read.return_value = json.dumps({"embedding": FAKE_EMBEDDING}).encode()
    mock_bedrock = MagicMock()
    mock_bedrock.invoke_model.return_value = {"body": fake_body}

    # OpenSearch mock — no moto support for AOSS
    mock_os = MagicMock()
    mock_os.indices.exists.return_value = True

    # Route bedrock-runtime to our mock; everything else goes through moto
    _real_client = boto3.client

    def _client(service, **kw):
        return mock_bedrock if service == "bedrock-runtime" else _real_client(service, **kw)

    with patch.object(ingest, "_get_opensearch_client", return_value=mock_os), \
         patch("boto3.client", side_effect=_client):
        response = ingest.lambda_handler(S3_EVENT, None)

    assert response["statusCode"] == 200
    assert json.loads(response["body"])["key"] == IMAGE_KEY

    item = table.get_item(Key={"image_key": IMAGE_KEY})["Item"]
    assert item["image_key"] == IMAGE_KEY
    assert "labels" in item
    assert "embedding" in item


# ---------------------------------------------------------------------------
# Search handler
# ---------------------------------------------------------------------------


def test_search_query_terms_tokenises():
    assert search._query_terms("beach sunset") == ["beach", "sunset"]
    assert search._query_terms("dog, cat!") == ["dog", "cat"]
    assert search._query_terms("A Dog") == ["a", "dog"]
    assert search._query_terms("") == []


def test_search_missing_query_returns_400():
    response = search.lambda_handler({"queryStringParameters": {}}, None)
    assert response["statusCode"] == 400
    assert "missing query" in json.loads(response["body"])["message"]


def test_search_count_returns_zero_when_no_index():
    mock_os = MagicMock()
    mock_os.indices.exists.return_value = False

    with patch.object(search, "_get_opensearch_client", return_value=mock_os):
        response = search.lambda_handler({"rawPath": "/count"}, None)

    assert response["statusCode"] == 200
    assert json.loads(response["body"])["count"] == 0
