# Globus Transfer Reference

## TransferClient Setup

```python
import globus_sdk

CLIENT_ID = "your-native-client-id"
app = globus_sdk.UserApp("my-transfer-app", client_id=CLIENT_ID)
tc = globus_sdk.TransferClient(app=app)
```

For managed collections that require data_access consent:
```python
tc = globus_sdk.TransferClient(app=app).add_app_data_access_scope(COLLECTION_ID)
# For transfers between two managed collections:
tc = globus_sdk.TransferClient(app=app).add_app_data_access_scope(
    (SRC_COLLECTION_ID, DST_COLLECTION_ID)
)
```

## Submitting a Transfer

```python
transfer_data = globus_sdk.TransferData(
    source_endpoint=SRC_COLLECTION_ID,
    destination_endpoint=DST_COLLECTION_ID,
    label="My transfer",
    sync_level="checksum",          # Options: "exists", "size", "mtime", "checksum"
    verify_checksum=False,          # Verify after transfer
    preserve_timestamp=False,       # Keep original timestamps
    encrypt_data=False,             # Encrypt data in transit
    # deadline="2025-12-31T23:59:59Z",  # Optional deadline
)

# Add individual files
transfer_data.add_item("/source/path/file.txt", "/dest/path/file.txt")

# Add directories (recursive by default in v4)
transfer_data.add_item("/source/path/dir/", "/dest/path/dir/")

# Submit
result = tc.submit_transfer(transfer_data)
task_id = result["task_id"]
print(f"Transfer submitted: {task_id}")
```

## Filter Rules for Transfers

```python
transfer_data = globus_sdk.TransferData(
    source_endpoint=SRC, destination_endpoint=DST,
)
transfer_data.add_item("/source/data/", "/dest/data/")

# Exclude certain file types
transfer_data.add_filter_rule("*.tmp", method="exclude", type="file")
transfer_data.add_filter_rule("*.log", method="exclude", type="file")

# Or include-only certain types (include rules + exclude-all)
transfer_data.add_filter_rule("*.csv", method="include", type="file")
transfer_data.add_filter_rule("*", method="exclude", type="file")
```

## Submitting a Delete

```python
delete_data = globus_sdk.DeleteData(
    endpoint=COLLECTION_ID,
    recursive=True,
    label="Cleanup old data",
)
delete_data.add_item("/path/to/delete/")
delete_data.add_item("/path/to/old_file.txt")

result = tc.submit_delete(delete_data)
print(f"Delete task: {result['task_id']}")
```

## Monitoring Tasks

```python
# Get task status
task = tc.get_task(task_id)
print(f"Status: {task['status']}")  # ACTIVE, SUCCEEDED, FAILED, INACTIVE

# Wait for completion (polling)
import time
while not tc.task_wait(task_id, timeout=60, polling_interval=10):
    task = tc.get_task(task_id)
    print(f"Still running... {task['nice_status']}")

# List recent tasks
for task in tc.task_list(limit=10):
    print(f"{task['task_id']}: {task['status']} - {task['label']}")

# List task events (for debugging)
for event in tc.task_event_list(task_id):
    print(f"{event['time']}: {event['description']}")
```

## Listing and Searching

```python
# List directory contents
for entry in tc.operation_ls(COLLECTION_ID, path="/share/godata/"):
    print(f"{entry['type']}: {entry['name']} ({entry['size']} bytes)")

# Search for endpoints/collections
for ep in tc.endpoint_search("Tutorial Collection"):
    print(f"{ep['id']}: {ep['display_name']}")

# Get endpoint details
ep = tc.get_endpoint(ENDPOINT_ID)
print(f"Name: {ep['display_name']}")
```

## Handling ConsentRequired Errors

With `UserApp`, consent is handled more gracefully, but you may still need to
handle it explicitly in some cases:

```python
try:
    result = tc.submit_transfer(transfer_data)
except globus_sdk.TransferAPIError as err:
    if err.info.consent_required:
        print("Additional consent needed for collections.")
        print("Required scopes:", err.info.consent_required.required_scopes)
        # With UserApp + auto_retry_gares=True, this is handled automatically
    else:
        raise
```

## Setting a Relative Deadline

```python
import datetime

def make_relative_deadline(offset: datetime.timedelta) -> str:
    now = datetime.datetime.now(tz=datetime.timezone.utc)
    return (now + offset).isoformat()

transfer_data = globus_sdk.TransferData(
    source_endpoint=SRC,
    destination_endpoint=DST,
    deadline=make_relative_deadline(datetime.timedelta(hours=1)),
)
```

## Important Notes

- `source_endpoint` and `destination_endpoint` are **collection IDs** (UUIDs), not
  endpoint IDs. In Globus v5, you interact with collections, not endpoints directly.
- The `transfer_client` parameter on `TransferData` is optional in v4. You can pass
  collection IDs directly as positional args.
- `recursive=True` on `add_item` is the default for directories in v4; you don't need
  to specify it explicitly for directory transfers.
- Use `sync_level="checksum"` for the most reliable sync behavior.
- Pagination: methods like `task_list`, `endpoint_search` return iterators. Call
  `list()` on them if you need to iterate multiple times.
