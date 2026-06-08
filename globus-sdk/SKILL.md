---
name: globus-sdk
description: >
  How to write Python code using the Globus SDK (globus-sdk v4+) and Globus Compute SDK
  (globus-compute-sdk) for research data management, transfer, compute, flows, and search.
  Use this skill whenever the user mentions Globus, globus_sdk, globus-sdk, globus-compute-sdk,
  globus_compute_sdk, Globus Transfer, Globus Flows, Globus Compute, Globus Search, GlobusApp,
  UserApp, ClientApp, FlowsClient, TransferClient, SearchClient, SpecificFlowClient,
  or any Globus service interaction in Python. Also trigger when the user has code using
  deprecated Globus patterns like NativeAppAuthClient manual OAuth flows, fair_research_login,
  globus-automate-client, or funcX — this skill knows the modern replacements. Even if the
  user doesn't say "Globus" explicitly, trigger if they mention research data transfer between
  HPC endpoints, collections, or writing automation flows for scientific data pipelines.
---

# Globus SDK Skill

This skill covers the modern Python interfaces for the Globus platform: `globus-sdk` (v4+)
for Transfer, Flows, Search, and Auth, and `globus-compute-sdk` for remote function execution.

## Critical: Deprecated Patterns to Avoid

**NEVER use these deprecated packages or patterns in new code:**

- **`fair_research_login`** — Replaced by `globus_sdk.UserApp` / `globus_sdk.ClientApp`. The
  `fair_research_login.client.NativeClient` class is obsolete. Migrate to `UserApp`.
- **`globus-automate-client`** — Archived Dec 2024. All flows functionality is now in
  `globus_sdk.FlowsClient` and `globus_sdk.SpecificFlowClient`. Do not use
  `globus_automate_client.FlowsClient` or any of its helpers.
- **Manual NativeAppAuthClient OAuth flows** — While `NativeAppAuthClient` still exists, the
  recommended approach for scripts and applications is `UserApp` (for interactive/user context)
  or `ClientApp` (for service accounts). These handle token storage, refresh, and consent
  automatically.
- **`funcx`** — Rebranded to Globus Compute. Use `globus_compute_sdk`, not `funcx`.
- **`SimpleJSONFileAdapter`** from `globus_sdk.tokenstorage` — While not removed, `UserApp`
  handles token storage automatically with sensible defaults (`"json"` storage). You generally
  don't need to manage token storage manually.

## Authentication: UserApp and ClientApp

The `GlobusApp` abstraction (introduced Oct 2024) is the recommended way to handle auth.
Read `references/auth.md` for full details.

**Quick reference — UserApp (interactive scripts):**
```python
import globus_sdk

CLIENT_ID = "your-native-client-id"  # Register at developers.globus.org
app = globus_sdk.UserApp("my-script", client_id=CLIENT_ID)
transfer_client = globus_sdk.TransferClient(app=app)
# UserApp handles login prompts, token storage, and refresh automatically
```

**Quick reference — ClientApp (service accounts / automation):**
```python
import globus_sdk

CLIENT_ID = "your-confidential-client-id"
CLIENT_SECRET = "your-client-secret"
app = globus_sdk.ClientApp("my-service", client_id=CLIENT_ID, client_secret=CLIENT_SECRET)
transfer_client = globus_sdk.TransferClient(app=app)
```

**Key points:**
- A single `GlobusApp` instance can be shared across multiple service clients.
- `UserApp` stores tokens in a JSON file by default — no manual token management needed.
- Pass `app=app` to any service client constructor (`TransferClient`, `FlowsClient`,
  `SearchClient`, `AuthClient`, etc.).
- Context manager support: `with UserApp(...) as app:` ensures cleanup.
- **Not thread safe** — use one app per thread if needed.

## Service Reference Files

For detailed guidance on each Globus service, read the appropriate reference file:

| Service | Reference File | When to Read |
|---------|---------------|--------------|
| Transfer | `references/transfer.md` | File transfers, collection operations, `TransferData`, `DeleteData` |
| Flows | `references/flows.md` | Workflow automation, flow definitions, `FlowsClient`, `SpecificFlowClient` |
| Compute | `references/compute.md` | Remote function execution, `Executor`, endpoints |
| Search | `references/search.md` | Indexing metadata, querying, `SearchClient`, `SearchQuery` |
| Auth | `references/auth.md` | Detailed auth patterns, scopes, consent handling, `GlobusAppConfig` |

**Always read the relevant reference file(s) before writing Globus code.** The reference files
contain essential patterns, common pitfalls, and up-to-date API signatures.

## Package Installation

```bash
pip install globus-sdk           # Core SDK: Transfer, Flows, Search, Auth, Groups, Timers
pip install globus-compute-sdk   # Compute SDK (separate package)
```

The core `globus-sdk` package (v4+) includes `TransferClient`, `FlowsClient`, `SearchClient`,
`AuthClient`, `TimersClient`, `GroupsClient`, `UserApp`, `ClientApp`, and all related helpers.

The `globus-compute-sdk` is a separate package providing the `Executor` and `Client` for
remote function execution.

## Common Pattern: Multiple Services with One App

```python
import globus_sdk

CLIENT_ID = "your-client-id"
app = globus_sdk.UserApp("my-workflow", client_id=CLIENT_ID)

# All clients share the same app — login happens once
transfer_client = globus_sdk.TransferClient(app=app)
flows_client = globus_sdk.FlowsClient(app=app)
search_client = globus_sdk.SearchClient(app=app)
```

## Registering a Client ID

All Globus SDK usage requires a registered application:

1. Go to https://developers.globus.org
2. Create or select a Project
3. Add a new app:
   - **Native App** (check the box) → for scripts run by humans → use `UserApp`
   - **Confidential Client** (uncheck the box) → for services/automation → use `ClientApp`
4. Note the Client ID (and secret, for confidential clients)

## Error Handling

```python
try:
    result = transfer_client.submit_transfer(transfer_data)
except globus_sdk.TransferAPIError as err:
    if err.info.consent_required:
        # Handle consent required — UserApp does this automatically if configured
        print("Additional consent needed:", err.info.consent_required.required_scopes)
    else:
        raise
except globus_sdk.GlobusAPIError as err:
    print(f"API Error: {err.message} (HTTP {err.http_status})")
```
