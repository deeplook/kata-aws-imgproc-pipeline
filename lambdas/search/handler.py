import json
import os
import re

import boto3
from botocore.exceptions import ClientError, EndpointConnectionError
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth


_BEDROCK_CLIENT = None
_OS_CLIENT = None
INDEX_NAME = "photos"
TEXT_RESULT_LIMIT = 24
VECTOR_RESULT_LIMIT = 5


def _get_bedrock_client():
    global _BEDROCK_CLIENT
    if _BEDROCK_CLIENT is None:
        _BEDROCK_CLIENT = boto3.client("bedrock-runtime")
    return _BEDROCK_CLIENT


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


def _query_terms(query: str) -> list[str]:
    return [term for term in re.split(r"[^a-z0-9]+", query.lower()) if term]


def _search_by_labels(client, query: str) -> list[dict]:
    terms = _query_terms(query)
    if not terms:
        return []

    should = []
    for term in terms:
        # Rekognition labels are stored as keyword arrays, so prefer exact
        # case variants first, then allow substring matches for looser queries.
        should.extend(
            [
                {"term": {"labels": {"value": term, "boost": 6}}},
                {"term": {"labels": {"value": term.title(), "boost": 8}}},
                {
                    "wildcard": {
                        "labels": {"value": f"*{term}*", "case_insensitive": True, "boost": 2}
                    }
                },
            ]
        )

    search_response = client.search(
        index=INDEX_NAME,
        body={
            "size": TEXT_RESULT_LIMIT,
            "query": {
                "bool": {
                    "should": should,
                    "minimum_should_match": 1,
                }
            },
        },
    )

    return [
        {
            "key": hit["_source"]["image_key"],
            "score": hit["_score"],
            "labels": hit["_source"].get("labels", []),
        }
        for hit in search_response["hits"]["hits"]
    ]


def _search_by_embedding(client, query: str) -> list[dict]:
    bedrock = _get_bedrock_client()
    response = bedrock.invoke_model(
        modelId="amazon.titan-embed-image-v1",
        body=json.dumps({"inputText": query}),
        contentType="application/json",
        accept="application/json",
    )
    query_embedding = json.loads(response["body"].read())["embedding"]
    print(f"query embedding: {len(query_embedding)} dimensions")

    search_response = client.search(
        index=INDEX_NAME,
        body={
            "size": VECTOR_RESULT_LIMIT,
            "query": {
                "knn": {
                    "embedding": {
                        "vector": query_embedding,
                        "k": VECTOR_RESULT_LIMIT,
                    }
                }
            },
        },
    )

    return [
        {
            "key": hit["_source"]["image_key"],
            "score": hit["_score"],
            "labels": hit["_source"].get("labels", []),
        }
        for hit in search_response["hits"]["hits"]
    ]


def lambda_handler(event, context):
    if event.get("rawPath", "").endswith("/count"):
        try:
            client = _get_opensearch_client()
            count = (
                client.count(index=INDEX_NAME)["count"]
                if client.indices.exists(index=INDEX_NAME)
                else 0
            )
            return {"statusCode": 200, "body": json.dumps({"count": count})}
        except Exception as e:
            print(f"Count error: {e}")
            return {"statusCode": 200, "body": json.dumps({"count": 0})}

    params = event.get("queryStringParameters") or {}
    query = params.get("q", "").strip()
    if not query:
        return {"statusCode": 400, "body": json.dumps({"message": "missing query parameter 'q'"})}

    print(f"Search query: {query!r}")

    try:
        client = _get_opensearch_client()
        results = _search_by_labels(client, query)
        search_mode = "labels"
        if not results:
            results = _search_by_embedding(client, query)
            search_mode = "embedding"
        print(json.dumps({"query": query, "results": len(results)}))
        print(f"search mode: {search_mode}")
        return {"statusCode": 200, "body": json.dumps({"results": results})}

    except EndpointConnectionError as e:
        print(f"Connection error: {e}")
        return {"statusCode": 503, "body": json.dumps({"message": "Service unavailable"})}
    except ClientError as e:
        code = e.response["Error"]["Code"]
        print(f"AWS error [{code}]: {e}")
        return {"statusCode": 500, "body": json.dumps({"message": f"AWS error: {code}"})}
    except Exception as e:
        print(f"Unexpected error: {e}")
        return {"statusCode": 500, "body": json.dumps({"message": "Internal error"})}
