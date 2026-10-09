---
name: apigen-api
description: >
  Generates a .NET project (hexagonal architecture) from an OpenAPI spec by
  calling the ApiGen REST API (`POST /generator/file`) instead of the local
  CLI. Uses the wrapper script `scripts/apigen-api.sh` /
  `scripts/apigen-api.ps1` bundled with this skill, which requires the
  `APIGEN_API_KEY` environment variable. Use when the user asks to "generate
  the project using the API", "call the deployed apigen endpoint", "use
  the REST API instead of the CLI", or gives a deployed ApiGen URL and an
  apikey.
---

# Apigen REST API Skill

Generates a hexagonal .NET project from an OpenAPI spec by calling the
ApiGen REST API (`POST /generator/file`), instead of using the local CLI
(see the `apigen-cli` skill for that route). Useful when no CLI is installed or
you want to integrate against an already deployed instance (dev/staging/prod).

The API accepts only **one** parameter: `file` (multipart/form-data) with the
OpenAPI spec. There are no output or configuration flags — everything else
(database driver, mappings, binding) lives inside the spec via the
`x-apigen-*` extensions (same rules as the `apigen-cli` skill, Phase 2).

---

## Where this skill's scripts live

This skill bundles `scripts/apigen-api.sh` and `scripts/apigen-api.ps1`
**next to this very `SKILL.md`** (not at the root of any project). Once
installed with `npx skills add`, they live in the skill's own folder, which
depends on the agent used, for example:
- Claude Code: `.claude/skills/apigen-api/scripts/`
- Other agents supported by the `skills` CLI: `<agent-skills-folder>/apigen-api/scripts/`

If you don't know the exact path in the current project, locate it with:
```bash
find . -path '*apigen-api/scripts/apigen-api.sh'
```
```powershell
Get-ChildItem -Recurse -Filter apigen-api.ps1
```
In the examples below, `<path-to-this-skill>` is that folder (e.g.
`.claude/skills/apigen-api`).

---

## API key handling — non-negotiable rule

- The API key **always** comes from the `APIGEN_API_KEY` environment variable.
  Never write it in a command, in this file, in a `.md`, in a log,
  or in a message to the user.
- If the user pastes the key in the chat, use it only to export it to the
  session's environment variable — don't echo it back or leave it in
  any versioned file.
- Before generating, check that the variable exists:
  ```bash
  test -n "$APIGEN_API_KEY" && echo "set" || echo "APIGEN_API_KEY missing"
  ```
  ```powershell
  if ($env:APIGEN_API_KEY) { "set" } else { "APIGEN_API_KEY missing" }
  ```
  If it's missing, ask the user to export it and stop — don't ask for it so
  you can write it into the command yourself.
- If you need to persist it locally across sessions, use a **gitignored**
  `.env` (confirm that `.env`/`.env.*` are in `.gitignore` before
  creating one) — never a versioned file.
- The wrapper script (`scripts/apigen-api.sh` / `.ps1`) already reads the variable
  directly; don't duplicate the key as a script argument.

---

## Phase 1 — Resolve the endpoint URL

- **There is no default endpoint.** The wrapper doesn't assume any "well-known"
  URL — the target URL is **always required**, just like `APIGEN_API_KEY`.
- If the user gives a deployed URL, use it: `--url <url>` (bash) /
  `-Url <url>` (PowerShell), or export `APIGEN_API_URL` before invoking.
- If the user doesn't give a URL and `APIGEN_API_URL` isn't set, **don't
  invent or assume an endpoint** — ask for it before running. The script
  fails with a clear message if it's missing anyway.

## Phase 2 — Prepare/validate the OpenAPI spec

Same validation as the `apigen-cli` skill (Phase 2): review
`x-apigen-project`, `x-apigen-models`, `x-apigen-mapping`, `x-apigen-binding`
in the user's spec before calling the API. Don't invent content without
confirming with the user. If the `apigen-openapi-check` skill is installed,
use it first.

## Phase 3 — Run generation via the API

1. Confirm `APIGEN_API_KEY` is set (see above).
2. Confirm the target URL is resolved (Phase 1) — via `APIGEN_API_URL` or
   `--url`/`-Url`. Without it, don't run the wrapper: ask the user for it.
3. Run the wrapper (path per "Where this skill's scripts live"):

   ```bash
   <path-to-this-skill>/scripts/apigen-api.sh "<spec-path>" -o "<outdir>" --url "<url>" --unzip
   ```
   ```powershell
   <path-to-this-skill>/scripts/apigen-api.ps1 -Spec "<spec-path>" -OutDir "<outdir>" -Url "<url>" -Unzip
   ```
4. The script:
   - validates that the spec exists,
   - validates that `APIGEN_API_KEY` is set (fails with a clear message if not),
   - validates that the URL is set, no default (fails with a clear message if not),
   - creates `<outdir>` if it doesn't exist,
   - sends the multipart POST and saves `<outdir>/<spec-name>.zip`,
   - with `--unzip`/`-Unzip`, extracts into `<outdir>/<spec-name>/`.
5. If the HTTP status isn't 200, the script prints the error body
   (`ErrorsResponse`: `{"Errors":[{"message":...,"status":...}]}`) and exits
   with a non-zero code — report it to the user, don't assume success.

## Phase 4 — Post-generation

Same as `apigen-cli` Phase 4: if the spec uses `data-driver`
postgresql/mysql, remind the user that the generated project needs `DATABASE_URL`
at runtime. Suggest `dotnet build` to verify it compiles. Don't run the
project or touch real databases unless the user explicitly asks.

---

## Notes

- This skill is the "remote" equivalent of `apigen-cli` — same spec, same
  generated architecture, different invocation channel (HTTP instead of a
  local binary). Useful for CI/CD pipelines or environments without the CLI installed.
- No health/version endpoint is documented in this skill — if you
  need to check service availability before generating, use the
  instance's Swagger UI (`<base-url>/swagger`) manually.
