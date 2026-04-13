# Infrastructure Cost Analysis

## Current stack — idle cost (no images processed, no requests)

| Service | Monthly cost | Notes |
|---|---|---|
| **AOSS** | **~$700** | 4 OCUs minimum (2 indexing + 2 search, HA enabled by default) × $0.24/OCU-hr × 730 hrs |
| App Runner | ~$2.50 | Memory ($0.007/GB-hr × 0.5 GB) charged continuously; vCPU only billed during active requests |
| ECR | ~$0.10 | Docker image storage at $0.10/GB |
| Lambda | $0 | Pay per invocation only |
| API Gateway v2 | $0 | Pay per request only |
| DynamoDB (on-demand) | $0 | Pay per request only |
| S3 | $0 | Empty bucket |
| **Total** | **~$700** | Almost entirely AOSS |

AOSS is the only AWS-native serverless vector search service, but its minimum capacity
pricing makes it impractical for development or low-traffic workloads.

Setting `standby_replicas = "DISABLED"` on the collection halves the OCU count to 2
(single-AZ, no HA), reducing AOSS to ~$350/month — still expensive.

---

## Alternatives for vector storage + k-NN search

### OpenSearch Service managed — easiest migration
- **Cost:** ~$25/month (`t3.small.search`, single node)
- **Serverless:** No — fixed instance
- **Migration effort:** Minimal — same `opensearch-py` API, endpoint swap only
- **Downside:** Manual instance sizing, no auto-scaling

### RDS PostgreSQL + pgvector — cheapest managed DB
- **Cost:** ~$13/month (`db.t3.micro`) + ~$32/month NAT Gateway if Lambdas need VPC access
- **Serverless:** No
- **Migration effort:** Medium — swap `opensearch-py` for `psycopg2`, rewrite index/search queries
- **Downside:** VPC complexity and NAT cost erode the savings unless using RDS Data API

### Aurora Serverless v2 + pgvector
- **Cost:** ~$43/month minimum (0.5 ACU × $0.12/ACU-hr, does not scale to zero) + VPC/NAT
- **Serverless:** Yes (but no true scale-to-zero)
- **Migration effort:** Medium — same as RDS pgvector
- **Downside:** More expensive than plain RDS once VPC costs are included

### DynamoDB + brute-force cosine similarity in Lambda
- **Cost:** ~$0 (DynamoDB on-demand, no requests = no cost)
- **Serverless:** Yes
- **Migration effort:** Medium — store vectors as DynamoDB attributes, compute cosine similarity in Lambda by scanning all items
- **Downside:** Full table scan on every search — degrades beyond a few thousand images; not a real vector index

### Qdrant on EC2
- **Cost:** ~$8/month (`t3.micro`)
- **Serverless:** No
- **Migration effort:** Medium — swap `opensearch-py` for `qdrant-client`
- **Downside:** You manage the instance, persistence, and restarts

### Pinecone (free tier)
- **Cost:** $0 (1 index, 100k vectors)
- **Serverless:** Yes (managed by Pinecone)
- **Migration effort:** Medium — swap client library, auth via API key instead of IAM
- **Downside:** Not AWS-native; paid plans start at ~$70/month beyond free tier

### Qdrant Cloud (free tier) — best fit for this kata
- **Cost:** $0 (1 cluster, 1 GB RAM, 0.5 vCPU, persistent storage)
- **Serverless:** Yes (managed by Qdrant)
- **Migration effort:** Medium — swap `opensearch-py` for `qdrant-client`, auth via API key
- **Downside:** Not AWS-native; API key must be stored in Lambda env vars or Secrets Manager

---

## Summary

| Option | Idle cost | Serverless | AWS-native |
|---|---|---|---|
| AOSS (current) | ~$700/mo | Yes | Yes |
| OpenSearch managed | ~$25/mo | No | Yes |
| RDS + pgvector | ~$13/mo (+VPC) | No | Yes |
| Aurora Serverless v2 + pgvector | ~$43/mo (+VPC) | Yes* | Yes |
| DynamoDB + Lambda brute-force | ~$0 | Yes | Yes |
| Qdrant on EC2 | ~$8/mo | No | Yes |
| Pinecone free tier | $0 | Yes | No |
| **Qdrant Cloud free tier** | **$0** | **Yes** | **No** |

\* Aurora Serverless v2 does not scale to zero — minimum 0.5 ACU always running.

For a kata or low-traffic demo, **Qdrant Cloud free tier** offers the best combination of
zero cost, serverless operation, and purpose-built vector search performance.
For a production AWS workload requiring IAM auth and no external dependencies,
**OpenSearch managed on `t3.small.search`** is the pragmatic step down from AOSS.
