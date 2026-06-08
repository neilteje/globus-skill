# Globus Flows Reference

## Overview

Globus Flows lets you create automated, reusable, and sharable workflows. Flows are finite
state machines defined in JSON. The SDK provides two client classes:

- **`FlowsClient`** — Create, update, delete, and list flows; view and manage runs.
  Requires `manage_flows` scope.
- **`SpecificFlowClient`** — Start a specific flow and resume inactive runs. Requires
  the flow-specific `user` scope.

## CRITICAL: Deprecated Package

**Do NOT use `globus-automate-client`.** It was archived December 2024. All functionality
is now in `globus_sdk.FlowsClient` and `globus_sdk.SpecificFlowClient`.

## FlowsClient Setup

```python
import globus_sdk

CLIENT_ID = "your-client-id"
app = globus_sdk.UserApp("my-flows-app", client_id=CLIENT_ID)
flows_client = globus_sdk.FlowsClient(app=app)
```

## Flow Definition Format

Flow definitions are JSON finite state machines with two required fields:

```python
flow_definition = {
    "StartAt": "TransferFiles",      # Must match a key in States
    "States": {
        "TransferFiles": {
            "Type": "Action",
            "ActionUrl": "https://actions.globus.org/transfer/transfer",
            "Parameters": {
                "source_endpoint_id.$": "$.source_collection",
                "destination_endpoint_id.$": "$.destination_collection",
                "transfer_items": [
                    {
                        "source_path.$": "$.source_path",
                        "destination_path.$": "$.destination_path",
                    }
                ],
            },
            "ResultPath": "$.TransferResult",
            "End": True,
        }
    },
}
```

### State Types

- **Action** — Invoke an action provider (Transfer, Compute, Search, email, etc.)
  - Must have `ActionUrl` and `Parameters`
  - Must be terminal (`"End": True`) or transitional (`"Next": "StateName"`)
- **Pass** — Transform/manipulate run data without performing an action
- **Choice** — Branch based on conditions
- **Wait** — Pause for a specified duration
- **Fail** — Terminate the run with an error
- **ExpressionEval** — Evaluate expressions and perform calculations

### JSONPath References

Use `.$` suffix on parameter keys to reference run data via JSONPath:
```python
"Parameters": {
    "source_endpoint_id.$": "$.source_collection",   # From run input
    "label": "Static string value",                   # Static value (no .$)
}
```

## CRITICAL: Always Provide an Input Schema

**Every flow should have an `input_schema`.** This is a JSON Schema (Draft 7 variant)
that validates input when starting a flow. Benefits:

1. The Globus Web App generates a guided input form from the schema
2. Input validation prevents runs from failing due to bad input
3. It serves as documentation for what the flow expects

```python
input_schema = {
    "type": "object",
    "required": ["source_collection", "destination_collection", "source_path", "destination_path"],
    "properties": {
        "source_collection": {
            "type": "string",
            "format": "uuid",
            "title": "Source Collection ID",
            "description": "The Globus collection to transfer from",
        },
        "destination_collection": {
            "type": "string",
            "format": "uuid",
            "title": "Destination Collection ID",
        },
        "source_path": {
            "type": "string",
            "title": "Source Path",
        },
        "destination_path": {
            "type": "string",
            "title": "Destination Path",
        },
    },
    "additionalProperties": False,
}
```

### Special Schema Formats for the Web App

The Globus Web App recognizes special `format` values:

- `"format": "uuid"` — renders a UUID input field
- `"format": "globus-collection"` — renders a collection picker with path browser:
  ```python
  "source": {
      "type": "object",
      "format": "globus-collection",
      "required": ["id", "path"],
      "properties": {
          "id": {"type": "string", "format": "uuid"},
          "path": {"type": "string"},
      },
      "additionalProperties": False,
  }
  ```
- `"propertyOrder": ["field1", "field2"]` — controls the display order of fields

## Creating a Flow

```python
result = flows_client.create_flow(
    title="My Transfer Flow",
    definition=flow_definition,
    input_schema=input_schema,
    subtitle="Transfers data between collections",
    description="A reusable flow that transfers files from source to destination.",
    keywords=["transfer", "data-management"],
    # flow_starters=["urn:globus:auth:identity:USER_ID"],  # Who can run it
    # flow_administrators=["urn:globus:auth:identity:ADMIN_ID"],  # Who can manage it
)
flow_id = result["id"]
print(f"Created flow: {flow_id}")
```

## BEST PRACTICE: Reuse and Update Flows

**Do NOT recreate flows repeatedly.** Free users are limited to one flow.
Instead, update existing flows:

```python
# Update an existing flow's definition and schema
flows_client.update_flow(
    flow_id=EXISTING_FLOW_ID,
    title="Updated Transfer Flow",
    definition=updated_definition,
    input_schema=updated_schema,
)

# List your flows to find existing ones
for flow in flows_client.list_flows(filter_role="flow_owner"):
    print(f"{flow['id']}: {flow['title']}")
```

**Pattern: Create-or-update:**
```python
def deploy_flow(flows_client, title, definition, input_schema, flow_id=None):
    """Create a new flow or update an existing one."""
    if flow_id:
        return flows_client.update_flow(
            flow_id=flow_id,
            title=title,
            definition=definition,
            input_schema=input_schema,
        )
    else:
        return flows_client.create_flow(
            title=title,
            definition=definition,
            input_schema=input_schema,
        )
```

Store the flow ID (e.g., in a config file or environment variable) and reuse it.
Only create a new flow when genuinely deploying something new.

## Starting a Flow (Running It)

Starting a flow requires a `SpecificFlowClient`:

```python
specific_flow_client = globus_sdk.SpecificFlowClient(flow_id, app=app)

run_result = specific_flow_client.run_flow(
    body={
        "source_collection": "6c54cade-bde5-45c1-bdea-f4bd71dba2cc",
        "destination_collection": "31ce9ba0-176d-45a5-add3-f37d233ba47d",
        "source_path": "/share/godata/file1.txt",
        "destination_path": "/~/transferred_file.txt",
    },
    label="My flow run",
)
run_id = run_result["run_id"]
print(f"Started run: {run_id}")
```

## Monitoring Runs

```python
# Get run status
run = flows_client.get_run(run_id)
print(f"Status: {run['status']}")  # ACTIVE, SUCCEEDED, FAILED, INACTIVE

# List runs for a specific flow
for run in flows_client.list_runs(filter_flow_id=flow_id):
    print(f"{run['run_id']}: {run['status']}")

# Get the definition used for a specific run
run_def = flows_client.get_run_definition(run_id)
```

## Multi-Step Flow Example: Transfer then Compute

```python
flow_definition = {
    "StartAt": "Transfer",
    "States": {
        "Transfer": {
            "Type": "Action",
            "ActionUrl": "https://actions.globus.org/transfer/transfer",
            "Parameters": {
                "source_endpoint_id.$": "$.source_id",
                "destination_endpoint_id.$": "$.dest_id",
                "transfer_items": [
                    {
                        "source_path.$": "$.source_path",
                        "destination_path.$": "$.dest_path",
                    }
                ],
            },
            "ResultPath": "$.TransferResult",
            "Next": "Compute",
        },
        "Compute": {
            "Type": "Action",
            "ActionUrl": "https://compute.actions.globus.org/v2",
            "Parameters": {
                "endpoint.$": "$.compute_endpoint_id",
                "function.$": "$.function_id",
                "kwargs": {
                    "data_path.$": "$.dest_path",
                },
            },
            "ResultPath": "$.ComputeResult",
            "End": True,
        },
    },
}
```

## Hosted Action Providers

Common ActionUrls for use in flow definitions:

| Service | ActionUrl |
|---------|-----------|
| Transfer (transfer) | `https://actions.globus.org/transfer/transfer` |
| Transfer (delete) | `https://actions.globus.org/transfer/delete` |
| Transfer (ls) | `https://actions.globus.org/transfer/ls` |
| Transfer (mkdir) | `https://actions.globus.org/transfer/mkdir` |
| Transfer (set permission) | `https://actions.globus.org/transfer/set_permission` |
| Search ingest | `https://actions.globus.org/search/ingest` |
| Search delete | `https://actions.globus.org/search/delete` |
| Send notification email | `https://actions.globus.org/notification/notify` |
| Expression evaluation | `https://actions.globus.org/expression_eval` |
| Wait for user selection | `https://actions.globus.org/weboption/wait_for_option` |
| Globus Compute | `https://compute.actions.globus.org/v2` |
| DataCite Mint | `https://actions.globus.org/datacite/mint/doi` |

## RunAs — Acting as Different Users

By default, actions run as the user who started the run. You can change this:

- `"RunAs": "User"` — default, runs as the person who started the run
- `"RunAs": "Flow"` — runs as the flow's own identity (`FLOW_ID@clients.auth.globus.org`)
- `"RunAs": "CustomRole"` — runs as tokens passed at run-start under `_tokens.CustomRole`

Most common use: `"RunAs": "Flow"` to let the flow use its own permissions for
specific steps (e.g., setting share permissions the user doesn't have).

## Exception Handling in Flows

```python
"TransferState": {
    "Type": "Action",
    "ActionUrl": "https://actions.globus.org/transfer/transfer",
    "Parameters": { ... },
    "Catch": [
        {
            "ErrorEquals": ["ActionFailedException"],
            "Next": "HandleError",
        }
    ],
    "Next": "Success",
}
```

## Validating Flow Definitions

Use the Globus CLI to validate before deploying:
```bash
globus flows validate definition.json --input-schema schema.json
```

Or use the Flows IDE: https://globus.github.io/flows-ide
