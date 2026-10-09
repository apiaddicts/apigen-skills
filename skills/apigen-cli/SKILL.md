---
name: apigen-cli
description: >
  Installs and runs this repo's `apigen` CLI to generate a .NET project
  (hexagonal architecture: Api/Domain/Infrastructure + tests) from an
  OpenAPI definition. Helps prepare/validate the x-apigen-project,
  x-apigen-models, x-apigen-mapping and x-apigen-binding extensions in the spec before generating,
  handles the global tool installation (official install.sh/.ps1 installer,
  self-contained binary that does not require .NET, or dotnet tool install if an SDK is already
  installed, with a fallback to local build+pack if the package is not published on
  NuGet), runs
  `apigen <spec> -o <dir>` and extracts the result. Use when the user asks to
  "generate the project with apigen", "use the CLI to generate the API", "install the
  apigen CLI", "generate code from my OpenAPI", or similar.
---

# Apigen CLI Skill

Automates installation + usage of the `apigen` CLI (project `src/Command`, package
`ApiAddicts.Apigen`, global command `apigen`) to generate a hexagonal .NET
project from an OpenAPI spec.

Final CLI command (no subcommands):
```
apigen <openapi-path.yml|yaml|json> [-o|--outpath <dir>]
```
- Positional arg = path to the spec (YAML or JSON, auto-detected). If omitted, it generates
  a stub "template" project.
- `-o`/`--outpath` = output folder for the generated `.zip` (default: the executable's
  own directory — **always pass `-o` explicitly**, do not rely on the default).
- Generated project name = the spec's `info.title` (PascalCase, no spaces/hyphens).
  It is not a flag.
- Generated target framework: fixed at `net10.0`.

---

## Phase 1 — Ensure global installation of `apigen`

Two installation families, in order of preference. The NuGet route
(`dotnet tool install`) **requires the .NET SDK to be installed** — if
it is not, or you do not want to depend on it, go straight to the
official installer route (self-contained binary, does not need .NET at all).

1. Detect whether it is already installed, on the PATH:
   ```powershell
   Get-Command apigen -ErrorAction SilentlyContinue
   ```
   If it exists, skip to Phase 2.

2. If it is not on the PATH, check whether it is already installed at the
   official installer's default path (the PATH may not have been reloaded in
   this session):
   - Windows: `"$env:LOCALAPPDATA\apigen\bin\apigen.exe"`
   - Linux/macOS: `"$HOME/.apigen/bin/apigen"`
   If it exists there, invoke it by absolute path in this session (do not rely
   on the PATH having been reloaded).

3. If it does not exist anywhere, choose an installation route:

   **Route A — official installer (recommended, does not require .NET installed):**
   self-contained binary, ships with the runtime embedded.
   ```powershell
   irm https://raw.githubusercontent.com/apiaddicts/apigen.net/main/install.ps1 | iex
   ```
   ```bash
   curl -fsSL https://raw.githubusercontent.com/apiaddicts/apigen.net/main/install.sh | sh
   ```
   Installs to the default path from step 2. On Windows, the installer adds
   the folder to the user PATH but **requires restarting the terminal**
   for it to reload — within the same session, invoke it by absolute
   path.

   **Route B — `dotnet tool` (only if a .NET SDK is already installed):**
   ```powershell
   dotnet tool install -g ApiAddicts.Apigen
   ```
   **Note**: the repo has no confirmed CI/publish workflow — this
   package may not be published. If the command fails (`NU1101`/`not
   found` or similar), or if `dotnet` is simply not available, do not
   retry in a loop — use Route A, or the local build+pack fallback:
   ```powershell
   dotnet pack ./src/Command/Command.csproj -c Release -o ./nupkg
   dotnet tool install -g --add-source ./nupkg ApiAddicts.Apigen
   ```
   If it was already installed from a previous `./nupkg` (different version),
   use `dotnet tool update -g --add-source ./nupkg ApiAddicts.Apigen` instead
   of `install`. This fallback also requires `dotnet` — if it is not
   available, the only viable route is A.

4. Verify the installation:
   ```powershell
   Get-Command apigen
   ```
   (or `command -v apigen` / absolute path if the session PATH was not
   reloaded). Confirm to the user that it is available. Informational note
   (non-blocking): the version banner printed by the CLI comes from
   `Directory.Build.props` (`1.0.1`), which may not match the README badge
   (`1.0.0`) — this is a known mismatch in the repo, not an error in
   the skill.

---

## Phase 2 — Prepare/validate the OpenAPI spec

Locate the OpenAPI file the user wants to use (or use one of
`src/Generator/Examples/*.yml|json` as a reference/test: `api-example.yml`,
`api-hospital.yml`, `petstore.json`, `Petstore with Owners-enriched.yaml` — note,
the last one has spaces in its name, so it must be quoted).

There is no separate config file: all configuration lives as `x-apigen-*`
extensions inside the spec itself. Review the user's spec and point out (without
inventing content without confirming with the user) what is missing:

### `x-apigen-project` (root document level)
Project metadata + database driver.
```yaml
x-apigen-project:
  name: My Project
  description: Project description
  version: 1.0.0
  data-driver: postgresql   # postgresql | mysql | (omit = in-memory)
```
If missing, it is the first thing to add — without it, the project still generates
but with no explicit metadata and no persistence driver defined.

### `x-apigen-models` (components level, alongside the schemas)
Defines entities and their relational mapping.
```yaml
x-apigen-models:
  User:
    relational-persistence:
      table: users
    attributes:
      uuid:
        type: string
        format: uuid
        relational-persistence:
          primary-key: true
          autogenerated: true
      userName:
        type: string
```
Check that every entity that must be persisted has this defined, especially
the primary key (`primary-key: true`).

### `x-apigen-mapping` (schema level, on the DTO)
Binds a DTO (schema used in request/response) to an entity from `x-apigen-models`.
```yaml
components:
  schemas:
    userDataSchema:
      x-apigen-mapping:
        model: User
      type: object
      properties: ...
```
Check that every DTO exposed in the API has this binding pointing to a `model`
that exists in `x-apigen-models`.

### `x-apigen-binding` (path level)
Binds a group of endpoints to a model (controls the generated controller/service).
```yaml
paths:
  /users:
    x-apigen-binding:
      model: User
```
Check that every relevant path has it.

### Database connection
It is not part of the spec or the CLI — if `data-driver` is not in-memory, the connection
string is read at runtime by the generated project via the `DATABASE_URL` env var. Only
inform the user about this, do not configure it in this phase.

When gaps are detected: show the exact snippet to add (based on the examples
above) and ask for confirmation before editing the user's spec.

---

## Phase 3 — Run generation

1. Confirm/create an explicit output folder:
   ```powershell
   New-Item -ItemType Directory -Force -Path <outdir>
   ```
2. Run:
   ```powershell
   apigen "<spec-path>" -o "<outdir>"
   ```
3. Review the console output (Serilog) for diagnostic warnings from the OpenAPI
   parser. If something looks suspicious, there is also a rolling log at:
   `<executable-folder>\Logs\Apigen_Dotnet_{version}_.txt`
   (locate the executable folder with `(Get-Command apigen).Source`, look for
   `Logs` next to the actual `.dll`/tool if more detail is needed).
4. The CLI leaves a `.zip` in `<outdir>` named `<file-name-without-extension>.zip`
   (or `template.zip` if no spec was passed). Extract it:
   ```powershell
   Expand-Archive -Path "<outdir>\<name>.zip" -DestinationPath "<outdir>\<name>" -Force
   ```

---

## Phase 4 — Post-generation

- Remind the user: if they used `data-driver: postgresql|mysql`, they must set
  `DATABASE_URL` as an environment variable before running the generated project.
- Suggest verifying that it builds:
  ```powershell
  dotnet build "<outdir>\<name>\<name>.sln"
  ```
- Do not run `dotnet run` on the generated project or touch real databases
  unless the user explicitly asks.
