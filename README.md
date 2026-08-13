# Apigen skills

Skills de agente para [ApiGen](https://github.com/apiaddicts/apigen.net) —
el generador de proyectos .NET (arquitectura hexagonal) a partir de
definiciones OpenAPI. Estas skills **no reemplazan** a `apigen.net`, lo
automatizan: instalan/invocan su CLI o su REST API, validan que un OpenAPI
tenga lo que el generador realmente necesita, y ayudan a completar specs
nuevos con las extensiones `x-apigen-*` correctas.

Empaquetado para instalarse con [`npx skills`](https://github.com/vercel-labs/skills)
en cualquier agente compatible (Claude Code, Cursor, Codex, OpenCode, y más).

## Instalación

```bash
# Todas las skills, a Claude Code
npx skills add apiaddicts/apigen-skills --skill '*' -a claude-code

# Interactivo (elegís skills y agentes)
npx skills add apiaddicts/apigen-skills

# Desde una copia local (por ejemplo, mientras se prueba antes de publicar)
npx skills add ./apigen-skills
```

## Skills incluidas

| Skill | Qué hace |
|---|---|
| [`apigen-cli`](skills/apigen-cli) | Instala (si hace falta) y ejecuta el CLI `apigen` para generar un proyecto .NET hexagonal desde un OpenAPI. |
| [`apigen-api`](skills/apigen-api) | Genera el proyecto llamando a la REST API de ApiGen (`POST /generator/file`) en vez del CLI local — útil sin CLI instalado o contra una instancia ya desplegada. Trae bundleados `scripts/apigen-api.sh` / `.ps1`. |
| [`apigen-openapi-check`](skills/apigen-openapi-check) | Valida de forma determinista (script Python, no juicio del modelo) que un OpenAPI tenga las propiedades `x-apigen-*` que el generador realmente lee, antes de invocar el CLI o la API. Trae bundleado `scripts/apigen_openapi_check.py`. |
| [`apigen-openapi-enrich`](skills/apigen-openapi-enrich) | Redacta y agrega las extensiones `x-apigen-*` faltantes en un OpenAPI nuevo o incompleto, traduciendo el vocabulario estándar de OpenAPI al de ApiGen. |

Flujo típico: `apigen-openapi-enrich` (si el spec es nuevo) →
`apigen-openapi-check` (validar) → `apigen-cli` o `apigen-api` (generar).

## Dependencias externas por skill

- `apigen-cli`: requiere poder instalar el CLI `apigen` (instalador oficial
  de apigen.net, o `dotnet tool` si ya hay SDK de .NET).
- `apigen-api`: requiere una `APIGEN_API_KEY` (nunca se guarda en el repo,
  siempre variable de entorno) y la URL del endpoint desplegado
  (`APIGEN_API_URL` o `--url`/`-Url`) — no hay endpoint default.
- `apigen-openapi-check` / `apigen-openapi-enrich` (indirectamente, vía
  check): requieren Python 3, y PyYAML si el spec a validar es YAML
  (`pip install pyyaml`).

## Origen

Estas skills se desarrollaron y probaron para la presentación
[«Genera microservicios profesionales en .NET con agentes en metodología API First»](https://www.youtube.com/watch?v=BoA7h7mYHk8),
donde se muestra su uso en vivo.

Automatizan [`apigen.net`](https://github.com/apiaddicts/apigen.net), el
generador de proyectos .NET (arquitectura hexagonal) a partir de OpenAPI —
otro repositorio de la organización [apiaddicts](https://github.com/apiaddicts).
Estas skills no lo reemplazan: instalan/invocan su CLI o su REST API.
