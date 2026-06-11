# Globus SDK Authentication Reference

## UserApp vs ClientApp

| Feature | UserApp | ClientApp |
|---------|---------|-----------|
| Use case | Scripts run by humans | Services, automation, cron jobs |
| Client type | Native App (or confidential) | Confidential Client |
| Auth flow | Browser-based login prompt | Client credentials (no browser) |
| Identity | Acts as the logged-in user | Acts as the client/service account itself |
| Token storage | JSON file by default | JSON file by default |
| Refresh tokens | Optional (off by default) | N/A (uses short-lived access tokens) |

## Choose the Auth Model First

| Scenario | Use | Why |
|----------|-----|-----|
| Researcher runs a local script or notebook | `globus_sdk.UserApp` with a Native App client ID | Acts as the user, prompts in browser, stores/refreshes user tokens when configured |
| CLI tool used repeatedly by a human | `UserApp` with `request_refresh_tokens=True` | Avoids repeated browser login while preserving user context |
| Deployed service, cron job, CI, facility automation | `globus_sdk.ClientApp` with a Confidential Client | No browser, acts as the client identity |
| Service must operate on user-owned data | Usually `UserApp`, a flow run, or delegated/user consent design | Client credentials are not a substitute for user authorization |
| Multi-service workflow: Transfer + Search + Flows | One shared `GlobusApp` instance | One auth context; service clients declare scopes through the app |

Avoid writing code that starts with low-level token exchange. Start with the actor
and select `UserApp` or `ClientApp`; only drop lower when a task explicitly requires
custom OAuth machinery.

## UserApp In-Depth

```python
import globus_sdk
from globus_sdk import GlobusAppConfig

# Minimal usage
app = globus_sdk.UserApp("my-app", client_id="YOUR_NATIVE_CLIENT_ID")
tc = globus_sdk.TransferClient(app=app)

# With configuration
config = GlobusAppConfig(
    request_refresh_tokens=True,       # Persist sessions across script runs
    token_storage="json",              # Default; stores to ~/.globus/app/my-app/tokens.json
    # token_storage="memory",          # Don't persist tokens
    # token_storage="sqlite",          # SQLite storage
)
app = globus_sdk.UserApp("my-app", client_id="YOUR_CLIENT_ID", config=config)

# Context manager usage (recommended)
with globus_sdk.UserApp("my-app", client_id="YOUR_CLIENT_ID") as app:
    tc = globus_sdk.TransferClient(app=app)
    result = tc.endpoint_search("Tutorial Collection")
```

## ClientApp In-Depth

```python
import globus_sdk

# From explicit credentials
app = globus_sdk.ClientApp(
    "my-service",
    client_id="YOUR_CONFIDENTIAL_CLIENT_ID",
    client_secret="YOUR_CLIENT_SECRET",
)
tc = globus_sdk.TransferClient(app=app)

# From environment variables (common in deployment)
import os
app = globus_sdk.ClientApp(
    "my-service",
    client_id=os.environ["GLOBUS_CLIENT_ID"],
    client_secret=os.environ["GLOBUS_CLIENT_SECRET"],
)
```

**Important:** ClientApp acts as the service account itself, not as any human user.
The identity is `{CLIENT_ID}@clients.auth.globus.org`. Permissions must be granted
to this identity explicitly.

## Scope Requirements

When using `app=app`, clients automatically register their default scopes. For
operations requiring additional scopes (e.g., data access on managed collections),
you need to add scope requirements:

```python
# For Transfer with data_access on specific collections
app = globus_sdk.UserApp("my-app", client_id=CLIENT_ID)
tc = globus_sdk.TransferClient(app=app)

# Add data_access scope for a managed collection
tc.add_app_data_access_scope(COLLECTION_ID)
# Or for multiple collections at once:
tc.add_app_data_access_scope((COLLECTION_ID_1, COLLECTION_ID_2))

# For FlowsClient + SpecificFlowClient combined usage, you may need
# to supply scope_requirements upfront:
app = globus_sdk.UserApp(
    "my-app",
    client_id=CLIENT_ID,
    scope_requirements={
        globus_sdk.FlowsClient.resource_server: [
            globus_sdk.FlowsClient.scopes.manage_flows
        ],
    },
)
```

### Scope and Consent Workflow

When generating or debugging code:

1. List every service touched: Transfer, Search, Flows, Compute, Groups, Timers.
2. For Transfer, identify every collection that requires `data_access`.
3. Add collection data access scopes before the operation:

```python
tc = globus_sdk.TransferClient(app=app)
tc.add_app_data_access_scope((source_collection_id, destination_collection_id))
```

4. For Flows management, request `FlowsClient.scopes.manage_flows` only when the
   code creates or updates flows. Starting a flow needs the flow-specific user
   scope through `SpecificFlowClient`.
5. For Search ingest/admin operations, use the Search scopes required by the SDK
   client and index permissions. Query-only code should not over-request admin
   capability.
6. Handle `ConsentRequired`/GARE by surfacing `required_scopes`; do not swallow
   the error or retry with the same scopes forever.

## Migrating from Deprecated Patterns

### From fair_research_login

```python
# OLD (deprecated)
from fair_research_login.client import NativeClient
cli = NativeClient(client_id=CLIENT_ID, app_name="My App")
cli.login(requested_scopes=[...])
tc = TransferClient(authorizer=cli.get_authorizers()["transfer.api.globus.org"])

# NEW
import globus_sdk
app = globus_sdk.UserApp("My App", client_id=CLIENT_ID)
tc = globus_sdk.TransferClient(app=app)
```

### From manual NativeAppAuthClient OAuth

```python
# OLD (verbose, manual)
auth_client = globus_sdk.NativeAppAuthClient(CLIENT_ID)
auth_client.oauth2_start_flow(requested_scopes=SCOPES)
url = auth_client.oauth2_get_authorize_url()
print(f"Login here: {url}")
code = input("Enter code: ")
tokens = auth_client.oauth2_exchange_code_for_tokens(code)
authorizer = globus_sdk.AccessTokenAuthorizer(tokens.by_resource_server[...]["access_token"])
tc = globus_sdk.TransferClient(authorizer=authorizer)

# NEW (handles everything automatically)
app = globus_sdk.UserApp("my-script", client_id=CLIENT_ID)
tc = globus_sdk.TransferClient(app=app)
```

### From ConfidentialAppAuthClient manual flow

```python
# OLD
confidential_client = globus_sdk.ConfidentialAppAuthClient(CLIENT_ID, CLIENT_SECRET)
tokens = confidential_client.oauth2_client_credentials_tokens(
    requested_scopes=globus_sdk.TransferClient.scopes.all
)
authorizer = globus_sdk.AccessTokenAuthorizer(
    tokens.by_resource_server["transfer.api.globus.org"]["access_token"]
)
tc = globus_sdk.TransferClient(authorizer=authorizer)

# NEW
app = globus_sdk.ClientApp("my-service", client_id=CLIENT_ID, client_secret=CLIENT_SECRET)
tc = globus_sdk.TransferClient(app=app)
```

## GARE (Globus Auth Requirements Error) Handling

UserApp can automatically retry on consent-required errors:

```python
config = GlobusAppConfig(auto_retry_gares=True)
app = globus_sdk.UserApp("my-app", client_id=CLIENT_ID, config=config)
```

When `auto_retry_gares=True`, if an API call fails because additional consent
is needed, the app will automatically prompt the user to login again with the
required scopes and retry the call.

For batch jobs, fail clearly and log the missing scopes rather than prompting:

```python
try:
    task_doc = tc.submit_transfer(transfer_data)
except globus_sdk.TransferAPIError as err:
    if err.info.consent_required:
        required = err.info.consent_required.required_scopes
        raise RuntimeError(f"Additional Globus consent required: {required}") from err
    raise
```

## Interactive Research Script Template

```python
import globus_sdk
from globus_sdk import GlobusAppConfig

CLIENT_ID = "YOUR_NATIVE_CLIENT_ID"

config = GlobusAppConfig(
    request_refresh_tokens=True,
    auto_retry_gares=True,
)

with globus_sdk.UserApp("my-research-workflow", client_id=CLIENT_ID, config=config) as app:
    transfer_client = globus_sdk.TransferClient(app=app)
    search_client = globus_sdk.SearchClient(app=app)

    # Add data_access scopes before touching protected collections.
    transfer_client.add_app_data_access_scope("SOURCE_COLLECTION_UUID")
    transfer_client.add_app_data_access_scope("DEST_COLLECTION_UUID")

    # Continue with ls, transfer, search ingest/query, or flow startup.
```

Operational notes:

- Use a stable app name; changing it can create a separate token storage location.
- `auto_retry_gares=True` is useful for scripts because the app can prompt again
  when a service reports missing consent.
- Request refresh tokens only when the workflow benefits from durable sessions.
  For one-off examples, default token storage is usually enough.
- Do not print access tokens or client secrets. Print task IDs, run IDs, and
  required scopes instead.

## Service Automation Template

```python
import os

import globus_sdk

app = globus_sdk.ClientApp(
    "facility-indexer",
    client_id=os.environ["GLOBUS_CLIENT_ID"],
    client_secret=os.environ["GLOBUS_CLIENT_SECRET"],
)

transfer_client = globus_sdk.TransferClient(app=app)
search_client = globus_sdk.SearchClient(app=app)
```

Before using this pattern, make the generated code explain the permission model:

- The identity is the client identity, not the human operator.
- Collections, groups, Search indices, and flows must grant permissions to the
  client identity where supported.
- For user-owned data, design for explicit user consent or a flow rather than
  assuming the client can impersonate users.
- Secrets belong in environment variables, a secret manager, or deployment config,
  never inline examples.

## Common Auth Failure Modes

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| `ConsentRequired` or GARE | Missing service or collection-specific scope | Add the relevant app scope; enable `auto_retry_gares` for interactive scripts |
| 403 from Transfer on a collection | User/client lacks collection permission or `data_access` consent | Verify collection ACLs and add data access scope before the operation |
| Service account can authenticate but cannot access data | Permissions were granted to a human, not the client identity | Grant access to `{CLIENT_ID}@clients.auth.globus.org` where applicable |
| Browser prompt appears in automation | Code used `UserApp` where `ClientApp` is required | Switch to `ClientApp` and load credentials from deployment secrets |
| Works once, fails on next run | Tokens not persisted or refresh tokens not requested | Use stable app name and `request_refresh_tokens=True` for durable human sessions |
| Agent emits `NativeAppAuthClient` or `fair_research_login` | Deprecated training-data pattern | Rewrite to `UserApp`/`ClientApp` |

## Security Defaults for Generated Code

- Put `CLIENT_ID` in config; put `CLIENT_SECRET` only in env/secrets.
- Never log tokens, authorization codes, or secrets.
- Persist IDs needed for recovery: Transfer task IDs, Flow run IDs, Search task IDs,
  function IDs, index IDs.
- Prefer least privilege: query examples should not request ingest/admin scopes;
  ingest examples should not request flow-management scopes unless they create flows.
- Explain who owns each operation: user identity, client identity, group, or flow
  run actor.

## Research Workflow Auth Heuristics

- Data publication/catalog workflows usually need Transfer plus Search. Model
  collection permissions, Search index permissions, and metadata visibility together.
- Facility pipelines often need a service identity for automation, but human
  researchers still need group-based visibility and clear provenance.
- Compute-adjacent workflows need separate attention to endpoint authorization and
  Python environment setup; Globus Auth succeeding does not prove the endpoint can
  execute the submitted function.
- Flows are useful when the workflow needs reusable, shareable, auditable user
  authorization boundaries across Transfer, Compute, Search, and notifications.
