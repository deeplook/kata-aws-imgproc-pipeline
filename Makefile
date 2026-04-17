## Usage: make [target]

SHELL := /bin/bash
IMAGE ?= test-image.jpg
QUERY ?= beach

.PHONY: help
help:
	@echo "Targets:"
	@echo "  install        Install Python dependencies with uv"
	@echo "  test           Run the local Python test suite"
	@echo "  fmt            Format Terraform code"
	@echo "  validate       Validate Terraform configuration"
	@echo "  plan           Create a Terraform execution plan"
	@echo "  setup          Initialize Terraform"
	@echo "  package        Build Lambda zip archives with dependencies"
	@echo "  deploy         Apply the Terraform configuration"
	@echo "  destroy        Destroy the Terraform-managed infrastructure"
	@echo "  upload         Upload a test image to S3 (IMAGE=path/to/file.jpg)"
	@echo "  logs-ingest    Tail CloudWatch logs for the ingest Lambda"
	@echo "  logs-search    Tail CloudWatch logs for the search Lambda"
	@echo "  wait-opensearch  Poll until OpenSearch collection is ACTIVE"
	@echo "  search         curl the search endpoint (QUERY=beach)"
	@echo "  smoke-ingest   Poll CloudWatch until ingest pipeline succeeds"
	@echo "  smoke-search   curl the search endpoint and assert results"
	@echo "  open-gallery   Open the App Runner gallery in a browser"
	@echo "  smoke-frontend Assert the gallery web app returns HTTP 200"
	@echo "  e2e            Full lifecycle: deploy, upload, smoke-ingest, search, smoke-search, smoke-frontend, destroy"
	@echo "  clean          Remove build artifacts and caches"

.PHONY: install
install:
	uv sync

.PHONY: test
test:
	uv run pytest

.PHONY: fmt
fmt:
	cd terraform && terraform fmt -recursive

.PHONY: validate
validate:
	cd terraform && terraform validate

.PHONY: plan
plan:
	cd terraform && terraform plan

.PHONY: setup
setup:
	cd terraform && terraform init

.PHONY: package
package:
	@echo "==> Packaging ingest Lambda..."
	@rm -rf lambdas/ingest/package lambdas/ingest/handler.zip
	@uv pip install \
		--target lambdas/ingest/package \
		--quiet \
		opensearch-py requests-aws4auth boto3
	@cp lambdas/ingest/handler.py lambdas/ingest/package/
	@cd lambdas/ingest/package && zip -r ../handler.zip . -x "*.pyc" -x "__pycache__/*"
	@echo "==> Packaging search Lambda..."
	@rm -rf lambdas/search/package lambdas/search/handler.zip
	@uv pip install \
		--target lambdas/search/package \
		--quiet \
		opensearch-py requests-aws4auth boto3
	@cp lambdas/search/handler.py lambdas/search/package/
	@cd lambdas/search/package && zip -r ../handler.zip . -x "*.pyc" -x "__pycache__/*"
	@echo "==> Lambda zips ready."

.PHONY: deploy
deploy: setup package
	cd terraform && terraform apply -auto-approve
	@echo "export S3_BUCKET=$$(cd terraform && terraform output -raw s3_bucket_name)" > .tf_outputs.env
	@echo "export DYNAMODB_TABLE=$$(cd terraform && terraform output -raw dynamodb_table_name)" >> .tf_outputs.env
	@echo "export INGEST_LAMBDA=$$(cd terraform && terraform output -raw ingest_lambda_name)" >> .tf_outputs.env
	@echo "export OPENSEARCH_ENDPOINT=$$(cd terraform && terraform output -raw opensearch_endpoint)" >> .tf_outputs.env
	@echo "export SEARCH_LAMBDA=$$(cd terraform && terraform output -raw search_lambda_name)" >> .tf_outputs.env
	@echo "export API_URL=$$(cd terraform && terraform output -raw api_url)" >> .tf_outputs.env
	@echo "export GALLERY_URL=$$(cd terraform && terraform output -raw gallery_url)" >> .tf_outputs.env

.PHONY: destroy
destroy:
	cd terraform && terraform destroy -auto-approve
	rm -f .tf_outputs.env

.PHONY: upload
upload:
	@if [ ! -f .tf_outputs.env ]; then \
		echo "Outputs file not found. Please run 'make deploy' first."; \
		exit 1; \
	fi
	@. .tf_outputs.env && \
	( \
		if [ ! -f "$(IMAGE)" ]; then \
			echo "Test image '$(IMAGE)' not found. Downloading..."; \
			curl -sL -o $(IMAGE) "https://upload.wikimedia.org/wikipedia/commons/thumb/4/47/PNG_transparency_demonstration_1.png/280px-PNG_transparency_demonstration_1.png"; \
		fi; \
		echo "Uploading $(IMAGE) to s3://$$S3_BUCKET/..."; \
		aws s3 cp $(IMAGE) s3://$$S3_BUCKET/$(IMAGE); \
		echo "Upload complete — run 'make logs-ingest' to watch the pipeline"; \
	)

.PHONY: logs-ingest
logs-ingest:
	@if [ ! -f .tf_outputs.env ]; then \
		echo "Outputs file not found. Please run 'make deploy' first."; \
		exit 1; \
	fi
	@. .tf_outputs.env && \
	aws logs tail "/aws/lambda/$$INGEST_LAMBDA" --follow

.PHONY: logs-search
logs-search:
	@if [ ! -f .tf_outputs.env ]; then \
		echo "Outputs file not found. Please run 'make deploy' first."; \
		exit 1; \
	fi
	@. .tf_outputs.env && \
	aws logs tail "/aws/lambda/$$SEARCH_LAMBDA" --follow

.PHONY: wait-opensearch
wait-opensearch:
	@if [ ! -f .tf_outputs.env ]; then \
		echo "Outputs file not found. Please run 'make deploy' first."; \
		exit 1; \
	fi
	@. .tf_outputs.env && \
	echo "Waiting for OpenSearch collection to become ACTIVE..."; \
	for i in $$(seq 1 30); do \
		STATUS=$$(aws opensearchserverless list-collections \
			--query "collectionSummaries[?name=='photo-gallery'].status" \
			--output text 2>/dev/null); \
		if [ "$$STATUS" = "ACTIVE" ]; then \
			echo "Collection is ACTIVE."; \
			exit 0; \
		fi; \
		echo "  status=$$STATUS (attempt $$i/30)..."; \
		sleep 20; \
	done; \
	echo "Collection did not become ACTIVE in time."; exit 1

.PHONY: search
search:
	@if [ ! -f .tf_outputs.env ]; then \
		echo "Outputs file not found. Please run 'make deploy' first."; \
		exit 1; \
	fi
	@. .tf_outputs.env && \
	curl -s "$$API_URL/search?q=$(QUERY)" | python3 -m json.tool

.PHONY: smoke-ingest
smoke-ingest:
	@if [ ! -f .tf_outputs.env ]; then \
		echo "Outputs file not found. Please run 'make deploy' first."; \
		exit 1; \
	fi
	@. .tf_outputs.env && \
	LOG_GROUP="/aws/lambda/$$INGEST_LAMBDA"; \
	echo "Polling $$LOG_GROUP for 'OpenSearch: indexed'..."; \
	for i in $$(seq 1 20); do \
		STREAM=$$(aws logs describe-log-streams \
			--log-group-name "$$LOG_GROUP" \
			--order-by LastEventTime --descending --limit 1 \
			--query "logStreams[0].logStreamName" --output text 2>/dev/null); \
		if [ -n "$$STREAM" ] && [ "$$STREAM" != "None" ]; then \
			if aws logs get-log-events \
				--log-group-name "$$LOG_GROUP" \
				--log-stream-name "$$STREAM" \
				--query "events[*].message" --output text 2>/dev/null \
				| grep -q "OpenSearch: indexed"; then \
				echo "smoke-ingest: PASSED"; exit 0; \
			fi; \
		fi; \
		echo "  attempt $$i/20 — not found yet, retrying in 10s..."; \
		sleep 10; \
	done; \
	echo "smoke-ingest: FAILED — 'OpenSearch: indexed' not found after 20 attempts"; exit 1

.PHONY: smoke-search
smoke-search:
	@if [ ! -f .tf_outputs.env ]; then \
		echo "Outputs file not found. Please run 'make deploy' first."; \
		exit 1; \
	fi
	@. .tf_outputs.env && \
	RESULTS=$$(curl -s "$$API_URL/search?q=$(QUERY)" \
		| python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('results', [])))"); \
	if [ "$$RESULTS" -gt 0 ]; then \
		echo "smoke-search: PASSED ($$RESULTS results for query '$(QUERY)')"; exit 0; \
	else \
		echo "smoke-search: FAILED (0 results for query '$(QUERY)')"; exit 1; \
	fi

.PHONY: open-gallery
open-gallery:
	@if [ ! -f .tf_outputs.env ]; then \
		echo "Outputs file not found. Please run 'make deploy' first."; \
		exit 1; \
	fi
	@. .tf_outputs.env && \
	echo "Opening $$GALLERY_URL" && \
	open "$$GALLERY_URL" 2>/dev/null || xdg-open "$$GALLERY_URL"

.PHONY: smoke-frontend
smoke-frontend:
	@if [ ! -f .tf_outputs.env ]; then \
		echo "Outputs file not found. Please run 'make deploy' first."; \
		exit 1; \
	fi
	@. .tf_outputs.env && \
	echo "Probing $$GALLERY_URL ..."; \
	for i in $$(seq 1 12); do \
		STATUS=$$(curl -s -o /dev/null -w "%{http_code}" "$$GALLERY_URL" 2>/dev/null); \
		if [ "$$STATUS" = "200" ]; then \
			echo "smoke-frontend: PASSED (HTTP 200)"; exit 0; \
		fi; \
		echo "  attempt $$i/12 — HTTP $$STATUS, retrying in 15s..."; \
		sleep 15; \
	done; \
	echo "smoke-frontend: FAILED — gallery did not return 200 after 12 attempts"; exit 1

.PHONY: e2e
e2e:
	make deploy
	make upload
	make smoke-ingest
	make search
	make smoke-search
	make smoke-frontend
	make destroy

.PHONY: clean
clean:
	@echo "Cleaning build artifacts and caches..."
	@rm -rf lambdas/ingest/package lambdas/ingest/handler.zip
	@rm -rf lambdas/search/package lambdas/search/handler.zip
	@rm -f test-image.jpg .tf_outputs.env
	@find terraform -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete 2>/dev/null || true
	@rm -rf .ruff_cache
	@echo "Clean complete."
