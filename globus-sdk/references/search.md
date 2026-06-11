# Globus Search Reference

## Overview

Globus Search provides a hosted search index service for research metadata. You can
create indices, ingest metadata documents, and query them with full-text search,
faceted filtering, and access-controlled visibility.

## Start With the Catalog Contract

Before writing SDK calls, define:

1. **Subject:** the stable identifier for each dataset, sample, run, file group,
   model, or publication. Prefer resolvable URIs or durable IDs.
2. **Entry IDs:** use `id` to separate metadata layers for the same subject
   (`"descriptive"`, `"provenance"`, `"quality"`, `"files"`).
3. **Visibility:** decide `visible_to` per record. Public records are not the same
   as records visible to a project group.
4. **Access pointers:** store collection IDs and paths when data should be fetched
   through Globus Transfer, but do not expose private paths in public records.
5. **Query surface:** choose fields users will filter/facet on, not just fields
   producers happen to emit.
6. **Lifecycle:** decide how records are updated, deleted, and reindexed when data
   moves or metadata extraction improves.

## Metadata Shape for Research Data

```python
def dataset_record(dataset):
    return {
        "subject": f"https://example.org/datasets/{dataset['id']}",
        "id": "descriptive",
        "visible_to": dataset["visible_to"],
        "content": {
            "title": dataset["title"],
            "description": dataset["description"],
            "domain": dataset["domain"],
            "keywords": dataset["keywords"],
            "creator": dataset["creator"],
            "created_at": dataset["created_at"],
            "instrument": dataset.get("instrument"),
            "file_count": dataset["file_count"],
            "size_bytes": dataset["size_bytes"],
            "globus": {
                "collection_id": dataset["collection_id"],
                "path": dataset["path"],
            },
            "provenance": {
                "workflow": dataset.get("workflow"),
                "compute_endpoint": dataset.get("compute_endpoint"),
                "software": dataset.get("software", []),
            },
        },
    }
```

Keep records boring and typed. Do not ingest one giant text blob if users need
facets over instrument, project, material, simulation parameters, date, or owner.

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

### Production Ingest Pattern

```python
import time

import globus_sdk


def ingest_records(search_client, index_id, records):
    payload = {
        "ingest_type": "GMetaList",
        "ingest_data": {"gmeta": records},
    }
    result = search_client.ingest(index_id, payload)
    task_id = result["task_id"]

    while True:
        task = search_client.get_task(task_id)
        if task["state"] == "SUCCESS":
            return task
        if task["state"] == "FAILED":
            raise RuntimeError(f"Search ingest failed: {task}")
        time.sleep(2)
```

Operational notes:

- Treat ingest as asynchronous. Persist the Search task ID for diagnostics.
- Batch records with `GMetaList`; single-record examples are fine for tutorials
  but poor defaults for production pipelines.
- Make ingest idempotent by using stable `subject` and `id` values.
- For updates, re-ingest the same `subject`/`id`. For removals, call delete APIs.
- For trial indices, expect administrative limits; generated code should not imply
  that every user can create unlimited production indices.

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

### Reusable Query Builder Pattern

```python
import globus_sdk


def build_dataset_query(text, *, domain=None, year_min=None, keywords=None, limit=25):
    query = globus_sdk.SearchQuery(q=text)
    query.set_limit(limit)

    if domain:
        query.add_filter("domain", [domain], type="match_all")

    if year_min:
        query.add_filter("year", [{"from": year_min, "to": "*"}], type="range")

    if keywords:
        query.add_filter("keywords", keywords, type="match_any")

    query.add_facet("Domains", "domain", size=20)
    query.add_facet("Keywords", "keywords", size=20)
    query.set_sort("created_at", order="desc")
    return query
```

Best practices:

- Use `post_search` with `SearchQuery` when filters/facets/sort matter.
- Add pagination parameters instead of assuming all results fit in one response.
- Keep query builders separate from rendering so CLI, notebook, and service code
  can reuse them.
- Print subject, title, score/rank where available, and enough access metadata for
  the next step; avoid dumping entire records by default.

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

## Visibility Patterns

| Need | `visible_to` Pattern |
|------|----------------------|
| Open metadata catalog | `["public"]` |
| Project-private catalog | `["urn:globus:groups:id:GROUP_UUID"]` |
| User-specific scratch results | `["urn:globus:auth:identity:USER_UUID"]` |
| Mixed public/private metadata | Separate entries with different `id` and `visible_to` values |

Do not make access-controlled data discoverable by accident. If a public record
points to controlled data, expose only high-level metadata and make the data access
path require Transfer permissions.

## Discovery to Transfer Pattern

When Search results contain Globus access pointers, generated workflows should:

1. Query Search for candidate datasets.
2. Let the user select a subject/result.
3. Extract `collection_id` and `path` from the selected record.
4. Add collection `data_access` scope to the `TransferClient` if required.
5. Submit a Transfer task to the user's destination collection.
6. Persist both the Search subject and Transfer task ID for provenance.

Search discovers data; Transfer authorizes and moves data. Do not treat a Search
hit as proof that the user can read the underlying files.

## Discovery to Compute Pattern

For compute-oriented examples:

1. Query Search for datasets matching metadata constraints.
2. Transfer or stage the selected data where the endpoint can read it.
3. Submit a Globus Compute function with explicit paths and metadata identifiers.
4. Ingest derived metadata back into Search under the same subject or a derived
   subject.

This pattern fits scientific pipelines where metadata discovery drives analysis,
but the generated code must still handle endpoint environment, package imports,
and serialization separately.

## Common Search Failure Modes

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Ingest task fails | Malformed GMeta payload or unsupported field values | Print/persist task doc; validate records before ingest |
| Query returns nothing | Record visibility excludes current identity or fields differ from query | Check `visible_to`, index ID, field names, and text vs structured filters |
| Public users see private paths | Public metadata included sensitive access pointers | Split public/private entries or remove private path details |
| Facets are empty or useless | Fields were ingested as inconsistent names/types | Normalize metadata schema before ingest |
| Duplicate-looking results | Multiple entries share one subject | Use entry `id` intentionally and render entries clearly |
| Agent creates new index every run | Missing lifecycle design | Reuse configured index IDs; create indices only during setup/deployment |

## Anti-Patterns to Avoid

- Do not create a new Search index inside every ingest script.
- Do not use random UUID subjects for datasets that need updates.
- Do not make all records public just to simplify examples.
- Do not hide ingest task monitoring; Search ingest is asynchronous.
- Do not hard-code user-specific collection paths in reusable examples.
- Do not write only full-text query examples when the task needs scientific
  filters, facets, and reproducible discovery.

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
