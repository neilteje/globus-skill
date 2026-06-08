# Globus Search Reference

## Overview

Globus Search provides a hosted search index service for research metadata. You can
create indices, ingest metadata documents, and query them with full-text search,
faceted filtering, and access-controlled visibility.

## SearchClient Setup

```python
import globus_sdk

CLIENT_ID = "your-client-id"
app = globus_sdk.UserApp("my-search-app", client_id=CLIENT_ID)
sc = globus_sdk.SearchClient(app=app)

# Or with explicit scopes for ingest operations:
sc = globus_sdk.SearchClient(
    app=app,
    app_scopes=[globus_sdk.Scope(globus_sdk.SearchClient.scopes.all)],
)
```

## Creating an Index

```python
result = sc.create_index(
    display_name="My Research Data Index",
    description="Searchable metadata for my research datasets",
)
index_id = result["id"]
print(f"Created index: {index_id}")
# Note: New indices are created in "trial" status.
# Contact support@globus.org to convert to non-trial with a subscription.
```

## Ingesting Data

### Single Document (GMetaEntry)

```python
ingest_data = {
    "ingest_type": "GMetaEntry",
    "ingest_data": {
        "subject": "https://example.com/dataset/001",
        "visible_to": ["public"],
        "content": {
            "title": "My Dataset",
            "author": "Jane Researcher",
            "year": 2025,
            "keywords": ["climate", "temperature", "ocean"],
            "file_count": 42,
        },
    },
}

result = sc.ingest(index_id, ingest_data)
task_id = result["task_id"]
print(f"Ingest task: {task_id}")
```

### Batch Ingest (GMetaList)

```python
ingest_data = {
    "ingest_type": "GMetaList",
    "ingest_data": {
        "gmeta": [
            {
                "subject": "https://example.com/dataset/001",
                "visible_to": ["public"],
                "content": {
                    "title": "Dataset One",
                    "type": "experimental",
                },
            },
            {
                "subject": "https://example.com/dataset/002",
                "visible_to": ["public"],
                "content": {
                    "title": "Dataset Two",
                    "type": "simulation",
                },
            },
            {
                "subject": "https://example.com/dataset/002",
                "id": "metadata-v2",  # Multiple entries per subject
                "visible_to": ["public"],
                "content": {
                    "title": "Dataset Two - Extended Metadata",
                    "resolution": "1km",
                },
            },
        ]
    },
}

result = sc.ingest(index_id, ingest_data)
```

### Key Concepts

- **subject** — A unique identifier for the thing being described (typically a URI).
  Multiple entries can share the same subject.
- **id** (optional) — Distinguishes multiple entries under the same subject. If
  omitted, defaults to a single entry per subject.
- **visible_to** — Controls access. Values:
  - `["public"]` — visible to anyone
  - `["urn:globus:auth:identity:USER_UUID"]` — specific user
  - `["urn:globus:groups:id:GROUP_UUID"]` — members of a Globus group
  - Multiple values for multiple grants

### Monitoring Ingest Tasks

Ingestion is asynchronous. Monitor the task:

```python
import time

task_id = result["task_id"]
while True:
    task = sc.get_task(task_id)
    if task["state"] in ("SUCCESS", "FAILED"):
        print(f"Task {task['state']}")
        break
    time.sleep(2)
```

## Querying / Searching

### Simple Text Search

```python
results = sc.search(index_id, q="climate ocean temperature")
for entry in results["gmeta"]:
    print(f"Subject: {entry['subject']}")
    for item in entry["entries"]:
        print(f"  Content: {item['content']}")
```

### Advanced Search with SearchQuery

```python
query = globus_sdk.SearchQuery(q="climate")

# Add filters
query.add_filter("year", [{"from": 2020, "to": 2025}], type="range")
query.add_filter("type", ["experimental"], type="match_all")

# Add facets
query.add_facet("Keyword Distribution", "keywords", size=10)
query.add_facet("Years", "year", type="date_histogram", date_interval="year")

# Sorting
query.set_sort("year", order="desc")

# Pagination
query.set_limit(10)
query.set_offset(0)

results = sc.post_search(index_id, query)

# Access results
print(f"Total: {results['total']}")
for entry in results["gmeta"]:
    print(entry["subject"])

# Access facets
for facet in results.get("facet_results", []):
    print(f"Facet: {facet['name']}")
    for bucket in facet["buckets"]:
        print(f"  {bucket['value']}: {bucket['count']}")
```

## Managing Indices

```python
# List your indices
for index in sc.index_list():
    print(f"{index['id']}: {index['display_name']} ({', '.join(index['permissions'])})")

# Get index info
index = sc.get_index(index_id)
print(f"Name: {index['display_name']}")
print(f"Entries: {index['num_entries']}, Size: {index['size_in_mb']}MB")

# Update index metadata
sc.update_index(index_id, display_name="Updated Name", description="New description")

# Delete an index (marks for deletion, not immediate)
sc.delete_index(index_id)
```

## Deleting Data

```python
# Delete a specific entry
sc.delete_entry(index_id, subject="https://example.com/dataset/001")

# Delete a specific sub-entry
sc.delete_entry(index_id, subject="https://example.com/dataset/002", entry_id="metadata-v2")

# Delete by query
sc.delete_by_query(index_id, {
    "q": "obsolete data",
    "filters": [
        {"type": "range", "field_name": "year", "values": [{"from": "*", "to": "2015"}]}
    ],
})

# Batch delete by subject
sc.batch_delete_by_subject(index_id, [
    "https://example.com/dataset/001",
    "https://example.com/dataset/002",
])
```

## Using Search in Flows

The Search Ingest action provider can be used in flow definitions:

```python
{
    "Type": "Action",
    "ActionUrl": "https://actions.globus.org/search/ingest",
    "Parameters": {
        "search_index": "your-index-uuid",
        "visible_to": ["public"],
        "subject.$": "$.document_subject",
        "content": {
            "title.$": "$.document_title",
            "processed_date.$": "$._context.run_started_at",
        },
    },
}
```

## Using Search with ClientApp (Service Account)

```python
import globus_sdk

app = globus_sdk.ClientApp(
    "ingest-service",
    client_id=CLIENT_ID,
    client_secret=CLIENT_SECRET,
)
sc = globus_sdk.SearchClient(
    app=app,
    app_scopes=[globus_sdk.Scope(globus_sdk.SearchClient.scopes.all)],
)

# The client identity needs writer/admin permissions on the index
# Grant via CLI: globus search index role create INDEX_ID writer CLIENT_ID@clients.auth.globus.org
```

## Important Notes

- **Ingest is async** — `sc.ingest()` returns a task ID, not confirmation that data
  is indexed. Always monitor the task if you need to query immediately after.
- **`create_entry` and `update_entry` are deprecated** — use `ingest()` instead.
- **visible_to is per-entry** — different entries under the same subject can have
  different visibility settings.
- **Trial indices are limited** — small size limit (1MB). Contact Globus support to
  upgrade with a subscription.
- **Field mappings** — for geospatial data, you can specify `field_mapping` in the
  ingest document to declare `geo_point` or `geo_shape` fields.
