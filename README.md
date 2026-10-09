# Apigen skills

Agent skills for [ApiGen](https://github.com/apiaddicts/apigen.net) —
the .NET project generator (hexagonal architecture) from OpenAPI
definitions. These skills **do not replace** `apigen.net`, they
automate it: they install/invoke its CLI or its REST API, validate that an
OpenAPI spec has what the generator actually needs, and help complete new
specs with the correct `x-apigen-*` extensions.

Packaged to be installed with [`npx skills`](https://github.com/vercel-labs/skills)
on any compatible agent (Claude Code, Cursor, Codex, OpenCode, and more).

## Installation

```bash
# All skills, to Claude Code
npx skills add apiaddicts/apigen-skills --skill '*' -a claude-code

# Interactive (pick skills and agents)
npx skills add apiaddicts/apigen-skills

# From a local copy (for example, while testing before publishing)
npx skills add ./apigen-skills
```

## Included skills

| Skill | What it does |
|---|---|
| [`apigen-cli`](skills/apigen-cli) | Installs (if needed) and runs the `apigen` CLI to generate a hexagonal .NET project from an OpenAPI spec. |
| [`apigen-api`](skills/apigen-api) | Generates the project by calling the ApiGen REST API (`POST /generator/file`) instead of the local CLI — useful without the CLI installed or against an already deployed instance. Bundles `scripts/apigen-api.sh` / `.ps1`. |
| [`apigen-openapi-check`](skills/apigen-openapi-check) | Deterministically validates (Python script, not model judgment) that an OpenAPI spec has the `x-apigen-*` properties the generator actually reads, before invoking the CLI or the API. Bundles `scripts/apigen_openapi_check.py`. |
| [`apigen-openapi-enrich`](skills/apigen-openapi-enrich) | Drafts and adds the missing `x-apigen-*` extensions to a new or incomplete OpenAPI spec, translating standard OpenAPI vocabulary into ApiGen's. |

Typical flow: `apigen-openapi-enrich` (if the spec is new) →
`apigen-openapi-check` (validate) → `apigen-cli` or `apigen-api` (generate).

## External dependencies per skill

- `apigen-cli`: requires being able to install the `apigen` CLI (official
  apigen.net installer, or `dotnet tool` if the .NET SDK is already present).
- `apigen-api`: requires an `APIGEN_API_KEY` (never stored in the repo,
  always an environment variable) and the URL of the deployed endpoint
  (`APIGEN_API_URL` or `--url`/`-Url`) — there is no default endpoint.
- `apigen-openapi-check` / `apigen-openapi-enrich` (indirectly, via
  check): require Python 3, plus PyYAML if the spec to validate is YAML
  (`pip install pyyaml`).

## Origin

These skills were developed and tested for the talk
[«Genera microservicios profesionales en .NET con agentes en metodología API First»](https://www.youtube.com/watch?v=BoA7h7mYHk8)
(“Generate professional .NET microservices with agents using an API First methodology”, in Spanish),
where their use is shown live.

They automate [`apigen.net`](https://github.com/apiaddicts/apigen.net), the
.NET project generator (hexagonal architecture) from OpenAPI —
another repository of the [apiaddicts](https://github.com/apiaddicts) organization.
These skills do not replace it: they install/invoke its CLI or its REST API.
