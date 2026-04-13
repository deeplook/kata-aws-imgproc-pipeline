import json


# TODO Stage 6: move Bedrock client to module scope (singleton pattern)
# TODO Stage 6: move OpenSearch client to module scope (singleton pattern)


def lambda_handler(event, context):
    # TODO Stage 8: add /count branch before the search logic
    # if event.get("rawPath", "").endswith("/count"):
    #     try:
    #         client = _get_opensearch_client()
    #         count = client.count(index=INDEX_NAME)["count"] if client.indices.exists(index=INDEX_NAME) else 0
    #         return {"statusCode": 200, "body": json.dumps({"count": count})}
    #     except Exception as e:
    #         print(f"Count error: {e}")
    #         return {"statusCode": 200, "body": json.dumps({"count": 0})}

    # TODO Stage 6: extract query string from event["queryStringParameters"]["q"]
    # TODO Stage 6: return 400 if query is missing or empty

    # TODO Stage 6: embed the query text using Bedrock titan-embed-image-v1
    # TODO Stage 6: run k-NN search against OpenSearch (k=5)
    # TODO Stage 6: format hits as [{"key": ..., "score": ..., "labels": ...}]
    # TODO Stage 6: return {"statusCode": 200, "body": json.dumps(results)}

    pass
