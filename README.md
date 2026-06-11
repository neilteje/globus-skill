# Globus SDK Skill

A Claude Code / Agent Skill that teaches Claude how to write correct, modern
Python against the Globus platform: Auth, Transfer, Search, Flows, and Globus
Compute SDK usage.

It steers generated code toward `globus-sdk` v4+ APIs, especially the
`GlobusApp` / `UserApp` / `ClientApp` auth model, and away from deprecated
patterns like `fair_research_login`, `globus-automate-client`, `funcx`, and
hand-rolled `NativeAppAuthClient` OAuth flows.

## Why

LLMs often emit outdated Globus examples because much of the public training data
predates the v4 SDK and recent deprecations. This skill gives Claude focused,
up-to-date reference material so generated code uses supported interfaces.

The skill also includes workflow-oriented guidance for:

- choosing `UserApp` vs `ClientApp`
- consent/GARE and collection `data_access` scopes
- secure token handling
- Search metadata catalog design
- `visible_to` and group visibility
- ingest/query lifecycle
- Search -> Transfer -> Compute provenance patterns

## What It Covers

| Area | Reference | Highlights |
|------|-----------|------------|
| Auth | [`globus-sdk/references/auth.md`](globus-sdk/references/auth.md) | `UserApp`, `ClientApp`, scopes, consent, service automation |
| Transfer | [`globus-sdk/references/transfer.md`](globus-sdk/references/transfer.md) | `TransferData`, `DeleteData`, filters, monitoring |
| Search | [`globus-sdk/references/search.md`](globus-sdk/references/search.md) | indices, ingest, `visible_to`, query builders, discovery workflows |
| Flows | [`globus-sdk/references/flows.md`](globus-sdk/references/flows.md) | `FlowsClient`, `SpecificFlowClient`, flow definitions |
| Compute SDK | [`globus-sdk/references/compute.md`](globus-sdk/references/compute.md) | `Executor`, functions, batches, `ShellFunction` |

Endpoint/HPC configuration for Globus Compute is intentionally out of scope for
this repo; that belongs in the separate `globus-compute-hpc` skill.

Academy agent workflows are also out of scope here; those now live in the
separate `globus-academy` skill package.

## Install

Copy or unzip the skill into your Claude Code skills directory:

```bash
unzip dist/globus-sdk.skill -d ~/.claude/skills/

# or from source:
cp -r globus-sdk ~/.claude/skills/
```

Restart Claude Code and ask something like:

> Write a Python script that transfers a file between two Globus collections.

## Repo Layout

```text
globus-skill/
├── globus-sdk/
│   ├── SKILL.md
│   └── references/
│       ├── auth.md
│       ├── transfer.md
│       ├── flows.md
│       ├── compute.md
│       └── search.md
├── dist/
│   └── globus-sdk.skill
└── scripts/
    └── build-skill.sh
```

## Develop

Edit Markdown under [`globus-sdk/`](globus-sdk/), then rebuild:

```bash
./scripts/build-skill.sh
```

The build output is `dist/globus-sdk.skill`, a zip archive whose top-level entry
is `globus-sdk/`.

## Writing Tips

- Keep `SKILL.md` trigger terms rich and specific.
- Put detailed service guidance in `globus-sdk/references/`.
- Prefer showing the supported pattern over only naming deprecated patterns.
- Keep this repo SDK-focused; put Academy and Compute endpoint/HPC material in
  their own skill repos.

## License

MIT.
