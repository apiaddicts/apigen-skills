---
name: apigen-openapi-enrich
description: >
  Adds/fixes the x-apigen-* extensions (x-apigen-project,
  x-apigen-models, x-apigen-mapping, x-apigen-binding) in a new or
  incomplete OpenAPI so that apigen.net generates it correctly, translating
  standard `type`/`format` into ApiGen's exact vocabulary and detecting
  entities/relationships from the schemas and paths. Use when the
  user asks "add the x-apigen properties to my OpenAPI", "complete my
  spec for apigen", "my OpenAPI is new, help me prepare it", or wants to
  fix the findings reported by the apigen-openapi-check skill.
---

# ApiGen OpenAPI Enrich Skill

Drafts and adds the `x-apigen-*` extensions an OpenAPI is missing
so that `apigen.net` generates it correctly. It complements
`apigen-openapi-check` (which only detects gaps): this skill **drafts the
content** and edits it into the spec.

**Explicit scope:** it only adds/fixes extensions. It does not install or
invoke the CLI/REST — it hands off to `apigen-cli` (CLI) or `apigen-api` (REST) once
the spec is ready. At the end of its flow it runs `apigen-openapi-check`
as verification; it does not reinvent those rules.

---

## Type vocabulary table — single source of truth

**`attributes[].type`** (case-insensitive, use exactly one of these —
any other value produces a nonexistent C# type that does not compile):

| ApiGen `type` | Resulting C# type |
|---|---|
| `Integer` / `Long` / `Number` | `long?` |
| `Boolean` | `bool?` |
| `LocalDate` / `LocalDateTime` | `DateTime?` |
| `String` | `string?` |
| `Array` | `List<{items-type}>?` |
| `Relation` | `{items-type}?` |

**Important — `x-apigen-models.attributes[].type` has no concept of
`format`.** The translation `type: String` + `format: date`/`date-time` →
`DateTime?` **only applies to the DTO** (the standard schema in
`components.schemas`, which does have `format`) — the function that translates
`x-apigen-models.attributes[].type` (`FormatTypeEntity`) never receives
`format`, so a date attribute in an entity must be declared
**explicitly** as `type: LocalDate` or `type: LocalDateTime`, never
`type: String` even if the equivalent field in the DTO has
`format: date-time` — using `String` there will generate `string?` in the entity
instead of `DateTime?`, silently.

**`attributes[].items-type`** — does **not** use this vocabulary, it is a **literal
C# token** substituted as-is:
- Array of scalars → real C# type name: `string`, `long`, `bool`,
  `DateTime` (never `String`/`Integer`/etc.).
- `Array`/`Relation` of a related entity → the **exact name
  (case-sensitive) of that entity's key** in `x-apigen-models` — it is not
  automatically Pascalized at this point, it must match literally.

**Entity naming rule:** decide each entity's name already in singular
PascalCase (e.g. `Pet`, not `pet` or `Pets`) and **reuse that same
literal string** in `x-apigen-models` (key), `x-apigen-binding.model`,
`x-apigen-mapping.model` and relationship `items-type`. Do not vary it from one
place to another — several parts of the generator compare the string as-is, not
Pascalized.

---

## Procedure

### 1. Read the user's spec

Review `components.schemas` and `paths`. If it already has some `x-apigen-*`, do not
overwrite it without confirming with the user first.

### 2. Verify/add `operationId` on every operation — before anything else

**This is not an `x-apigen-*` extension, it is a standard OpenAPI field, but
it is mandatory for ApiGen and was confirmed by breaking the generator
directly**: without `operationId`, `ControllersGenerator` blows up with
`ArgumentNullException` in `Humanizer.Pascalize` when generating the controller —
it is not a silent degradation, it is a hard crash. Many editors do not
flag it as mandatory, so it is easy for a new spec to lack it.

Before touching any `x-apigen-*` extension, go through **all**
operations (`get`/`post`/`put`/`patch`/`delete`/etc. of each path) and
propose a unique, descriptive `operationId` if missing (e.g. `getBooks`,
`createBook`, `getBookById`) — camelCase, verb + resource, no spaces.

### 3. Declare every used tag in the root `tags:` array — before continuing

**Another critical standard OpenAPI field (not `x-apigen-*`), confirmed by
generating and running the real project, not just reading code:** if two or
more operations share a tag (e.g. `tags: [books]`) and that name is **not**
declared in the document's root `tags:` array, the OpenAPI
reader creates a distinct tag object per operation even though the name is
the same. `ControllersGenerator` compares tags by object reference, not by
name — result: **only one of those operations survives in the
generated controller, the others silently disappear** (no
generation or compilation error, the project compiles just the same but is missing
endpoints).

Before proposing `x-apigen-binding`, go through all the `tags: [...]` used
in the operations and add one per distinct name to the root array:
```yaml
tags:
  - name: books
```
If the user's spec already has paths with the same tag repeated across several
operations and does **not** have this root array, treat it as a critical finding
just as urgent as a missing `x-apigen-models` — it is not optional even though
the spec is technically valid without it.

### 4. Propose `x-apigen-models` for each persisted entity

**Mandatory location: under `components`, not at the document root**
(`components.x-apigen-models`, sibling of `components.schemas`) —
confirmed with `apigen-openapi-check`: placed at the root, the checker
reports it as "missing or empty under 'components'" and the generator creates a
placeholder entity `Sample` instead of the real ones.
```yaml
components:
  x-apigen-models:
    Pet:
      attributes: { ... }
  schemas:
    PetDto: { ... }
```

One or more schemas can map to the same entity (e.g. `Pet`, `PetGet`,
`PetPost` → all to the `Pet` entity) — identify the set and a single
entity key for all of them.

For each schema property:
- Translate the OpenAPI `type`/`format` into the vocabulary of the table above.
- **Primary key:** heuristic — `id` property, or `format: uuid`. If it is
  ambiguous, ask the user instead of guessing. Mark with
  `relational-persistence.primary-key: true`.
- **Relationships** (`$ref` to another schema, or array of another schema): use
  `type: Relation` (one) or `type: Array` (many) + `items-type:
  <ExactEntityName>`. For it to be a real FK (not just navigation),
  add `relational-persistence.column` with a name **different** from
  the property's (e.g. property `owner` → column `owner_id`) — if the column
  name matches the property name, the generator does not treat it as an
  FK.
  - **Known generator limitation — warn, do not try to compensate:** the
    scalar FK column the generator creates for a relationship always
    ends up typed `long?`, regardless of the actual primary key type of
    the referenced entity (internal resolution bug). If the
    referenced entity has a non-numeric PK (e.g. `uuid`/`string`),
    warn the user about this explicitly — there is no combination of
    properties in the OpenAPI that fixes it, the generator would need a
    code fix.
- **Validations** — use standard OpenAPI keywords, never the
  `x-apigen-models.attributes[].validations` key (decorative, the generator does not
  read it):
  - `[StringLength]` comes from `minLength` **and** `maxLength` together (both or
    neither — only one activates nothing).
  - `[Range]` comes from `minimum` **and** `maximum` together (same case).
  - `format: date-time` on a `string` → `DataType.DateTime`; any
    other `format` on a string falls through to `DataType.Date` (there is no
    real mapping for `email`/`uuid`/etc. — do not promise that behavior).
  - `pattern` is never read, do not suggest it as if it had an effect.
- `relational-persistence.table` is optional — if omitted, EF Core uses the
  class/entity name as the table by default. Only add it if the
  user wants a different table name (e.g. explicit snake_case).

### 5. Propose `x-apigen-mapping` for each DTO

For each schema used as a request/response body in some path:
```yaml
components:
  schemas:
    PetDto:
      x-apigen-mapping:
        model: Pet
```

### 6. Propose `x-apigen-binding` for each path of the resource

`x-apigen-binding` only needs to be on one path per tag group for
the controller to be generated, but if two paths of the same tag declared different
models, only the first one appearing in the document wins for *all*
operations — to avoid that risk, **apply it to all paths of the
same resource**, not just one:
```yaml
paths:
  /pets:
    x-apigen-binding: { model: Pet }
  /pets/{id}:
    x-apigen-binding: { model: Pet }
```

### 7. Propose `x-apigen-project`

Ask the user whether they need PostgreSQL/MySQL or whether in-memory is fine:
```yaml
x-apigen-project:
  data-driver: postgresql   # or mysql / omit for in-memory
```
**Do not add** `name`/`description`/`version` — they are decorative,
confirmed as never read by the generator (`apigen-openapi-check` already
flags them as such). If the user insists on having them, clarify this before
adding them.

### 8. Confirm before editing

Present the full summary of what will be added (all
entities/mappings/bindings together, not field by field) and ask for **a** single
confirmation before touching the user's file.

### 9. Apply and verify

Apply the changes with `Edit`. Then run the validation skill/script
on the result — the validator lives in the `apigen-openapi-check` skill
(sibling folder `../apigen-openapi-check/scripts/`):
```bash
../apigen-openapi-check/scripts/apigen-openapi-check.sh "<spec-path>"
```
```powershell
../apigen-openapi-check/scripts/apigen-openapi-check.ps1 -Spec "<spec-path>"
```
If you do not know the exact path where both skills were installed, locate
the script with `find . -path '*apigen-openapi-check/scripts/apigen-openapi-check.sh'`
(Unix) or `Get-ChildItem -Recurse -Filter apigen-openapi-check.ps1` (Windows).

Report to the user whether it came out clean (0 CRITICAL) or whether something needs another
pass. Only then suggest continuing with `apigen-cli` / `apigen-api` to
generate the project.
