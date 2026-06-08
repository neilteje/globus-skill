# Globus Compute Reference

## Overview

Globus Compute is a distributed Function as a Service (FaaS) platform for executing Python
functions on remote compute resources (laptops, clusters, clouds, supercomputers).

**Package:** `globus-compute-sdk` (separate from `globus-sdk`)

```bash
pip install globus-compute-sdk
```

**IMPORTANT:** Do NOT use `funcx` — it has been rebranded to Globus Compute.

## The Executor (Recommended Interface)

The `Executor` class is recommended for most interactions. It uses AMQP streaming
for efficient result delivery (no polling).

```python
from globus_compute_sdk import Executor

def add(a, b):
    return a + b

endpoint_id = "your-endpoint-uuid"  # Or the tutorial endpoint for testing

with Executor(endpoint_id=endpoint_id) as gce:
    future = gce.submit(add, 5, 10)
    result = future.result()  # Blocks until result is ready
    print(result)  # 15
```

### Key Points About the Executor

- **Always use as a context manager** (`with Executor(...) as gce:`) or call
  `.shutdown()` explicitly. The executor cannot auto-detect when you're done.
- **One Executor per endpoint.** Create separate executors for different endpoints.
- **Submit returns a Future** — call `.result()` to get the value (blocks).
- **Functions must be self-contained** — import dependencies inside the function body.
- **Python version must match** between submitter and endpoint (at least minor version).

## Writing Compute Functions

### Dependencies Must Be Imported Inside the Function

```python
# CORRECT
def process_data(filepath):
    import pandas as pd
    import numpy as np
    df = pd.read_csv(filepath)
    return df.describe().to_dict()

# WRONG — imports at module level won't be available on the endpoint
import pandas as pd
def process_data(filepath):
    df = pd.read_csv(filepath)  # Will fail!
    return df.describe().to_dict()
```

### The Endpoint Must Have the Required Packages

The Python environment on the compute endpoint must have all packages your function
imports. If using `pandas`, it must be installed on the endpoint.

## Batch Submissions

```python
from globus_compute_sdk import Executor

def square(x):
    return x ** 2

with Executor(endpoint_id=endpoint_id) as gce:
    futures = [gce.submit(square, i) for i in range(100)]
    
    # Collect results in order
    results = [f.result() for f in futures]
    
    # Or use as_completed for results as they arrive
    from concurrent.futures import as_completed
    for future in as_completed(futures):
        try:
            result = future.result()
            print(result)
        except Exception as e:
            print(f"Task failed: {e}")
```

## ShellFunction (Running Shell Commands)

```python
from globus_compute_sdk import Executor
from globus_compute_sdk import ShellFunction

bf = ShellFunction("echo '{message}'")

with Executor(endpoint_id=endpoint_id) as gce:
    future = gce.submit(bf, message="Hello World!")
    shell_result = future.result()
    print(shell_result.returncode)  # Exit code
    print(shell_result.stdout)       # Standard output
    print(shell_result.cmd)          # The actual command run
```

## Function Registration

Functions are automatically registered on first `.submit()`. For explicit control:

```python
with Executor(endpoint_id=endpoint_id) as gce:
    function_id = gce.register_function(my_function)
    print(f"Function ID: {function_id}")
    
    # Later, submit using the registered function ID
    future = gce.submit_to_registered_function(function_id, args=(42,))
```

Pre-registering is useful when:
- The function is submitted from a different environment than where it was defined
- You want to share a function ID with others
- You need to use the function in a Globus Flow

## Using the Low-Level Client

For operations beyond the Executor (checking endpoint status, etc.):

```python
from globus_compute_sdk import Client

gcc = Client()

# Check endpoint status
status = gcc.get_endpoint_status(endpoint_id)
print(f"Status: {status}")

# Register a function
def my_func(x):
    return x * 2

func_id = gcc.register_function(my_func)
print(f"Registered function: {func_id}")
```

## Authentication for Compute

Globus Compute uses Globus Auth. First use will prompt for browser login.

### Client Credentials (for automation)

Set environment variables:
```bash
export GLOBUS_COMPUTE_CLIENT_ID="your-confidential-client-id"
export GLOBUS_COMPUTE_CLIENT_SECRET="your-client-secret"
```

When these are set, the `Client` and `Executor` will use them automatically.

## Using Compute in Flows

To invoke a Compute function from a Globus Flow, you need:
1. A registered function ID
2. A Compute endpoint ID

In the flow definition:
```python
{
    "Type": "Action",
    "ActionUrl": "https://compute.actions.globus.org/v2",
    "Parameters": {
        "endpoint": "compute-endpoint-uuid",
        "function": "registered-function-uuid",
        "kwargs": {
            "input_path": "/path/to/data",
        },
    },
    "ResultPath": "$.ComputeResult",
}
```

**Important:** The Compute endpoint must have the required Python packages installed
for the function to execute successfully.

## Endpoint Management

Endpoints are managed via the `globus-compute-endpoint` CLI (separate package):

```bash
pip install globus-compute-endpoint
globus-compute-endpoint configure my-endpoint
globus-compute-endpoint start my-endpoint
globus-compute-endpoint stop my-endpoint
```

Endpoint configuration is done via YAML files. The recommended engine is
`GlobusComputeEngine` (the `HighThroughputEngine` is deprecated and removed).

## Serialization

By default, Globus Compute uses `dill` for serialization. You can customize this:

```python
from globus_compute_sdk import Executor
from globus_compute_sdk.serialize import ComputeSerializer, PureSourceTextInspect, JSONData

with Executor(endpoint_id=endpoint_id) as gce:
    gce.serializer = ComputeSerializer(
        strategy_code=PureSourceTextInspect(),
        strategy_data=JSONData(),
    )
```

## Common Pitfalls

1. **Python version mismatch** — Submitter and endpoint must run the same Python minor
   version (e.g., both 3.11.x). Different minors (3.10 vs 3.11) can cause serialization
   failures or segfaults.
2. **Missing packages on endpoint** — All imports inside your function must be installed
   in the endpoint's Python environment.
3. **Large return values** — Results are sent over the network. Keep return values
   reasonable in size. Write large outputs to files instead.
4. **Global state** — Functions execute in isolated workers. Don't rely on global variables
   or module-level state from the submitter.
