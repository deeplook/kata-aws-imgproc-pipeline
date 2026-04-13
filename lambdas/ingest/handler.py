import json
import urllib.parse


# TODO Stage 4: move Bedrock client to module scope (singleton pattern)
# TODO Stage 5: move OpenSearch client to module scope (singleton pattern)


def lambda_handler(event, context):
    # TODO Stage 1: print a startup message
    # TODO Stage 1: print the full event as JSON
    # TODO Stage 1: parse bucket_name and object_key from event["Records"][0]["s3"]
    # TODO Stage 1: URL-decode the object key (urllib.parse.unquote_plus)
    # TODO Stage 1: return {"statusCode": 200, "body": json.dumps({"key": object_key})}

    # TODO Stage 2: create a Rekognition client
    # TODO Stage 2: call detect_labels (MaxLabels=10, MinConfidence=75)
    # TODO Stage 2: log each label as "  - <Name>: <Confidence:.2f>%"

    # TODO Stage 3: create a DynamoDB resource
    # TODO Stage 3: call put_item with image_key, labels, upload_timestamp

    # TODO Stage 4: call Bedrock invoke_model with amazon.titan-embed-image-v1
    # TODO Stage 4: extract embedding from response, log "embedding: N dimensions"
    # TODO Stage 4: update DynamoDB item with the embedding attribute

    # TODO Stage 5: create an OpenSearch client (opensearch-py + requests-aws4auth)
    # TODO Stage 5: create index if not exists (1024 dims, cosine, hnsw)
    # TODO Stage 5: index the document (image_key, labels, embedding)

    pass
