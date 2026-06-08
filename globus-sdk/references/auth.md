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
