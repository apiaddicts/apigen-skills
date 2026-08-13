---
name: apigen-api
description: >
  Genera un proyecto .NET (arquitectura hexagonal) a partir de un OpenAPI
  llamando a la REST API de ApiGen (`POST /generator/file`) en vez del CLI
  local. Usa el script wrapper `scripts/apigen-api.sh` /
  `scripts/apigen-api.ps1` bundleado con esta skill, que requiere la
  variable de entorno `APIGEN_API_KEY`. Usar cuando el usuario pida "genera
  el proyecto usando la API", "llama al endpoint de apigen desplegado", "usa
  la REST API en vez del CLI", o dé una URL de ApiGen desplegada y una
  apikey.
---

# Apigen REST API Skill

Genera un proyecto .NET hexagonal a partir de un spec OpenAPI llamando a la
REST API de ApiGen (`POST /generator/file`), en vez de usar el CLI local
(ver skill `apigen-cli` para esa vía). Útil cuando no hay CLI instalado o se
quiere integrar contra una instancia ya desplegada (dev/staging/prod).

La API solo acepta **un** parámetro: `file` (multipart/form-data) con el
OpenAPI. No hay flags de salida ni de configuración — todo lo demás
(driver de base de datos, mapeos, binding) vive dentro del spec vía las
extensiones `x-apigen-*` (mismas reglas que la skill `apigen-cli`, Fase 2).

---

## Dónde viven los scripts de esta skill

Esta skill trae bundleados `scripts/apigen-api.sh` y `scripts/apigen-api.ps1`
**junto a este mismo `SKILL.md`** (no en la raíz de ningún proyecto). Una vez
instalada con `npx skills add`, quedan en la carpeta propia de la skill según
el agente usado, por ejemplo:
- Claude Code: `.claude/skills/apigen-api/scripts/`
- Otros agentes soportados por el CLI `skills`: `<carpeta-de-skills-del-agente>/apigen-api/scripts/`

Si no conocés la ruta exacta en el proyecto actual, ubicala con:
```bash
find . -path '*apigen-api/scripts/apigen-api.sh'
```
```powershell
Get-ChildItem -Recurse -Filter apigen-api.ps1
```
En los ejemplos de abajo, `<ruta-a-esta-skill>` es esa carpeta (ej.
`.claude/skills/apigen-api`).

---

## Gestión de la apikey — regla no negociable

- La apikey **siempre** viene de la variable de entorno `APIGEN_API_KEY`.
  Nunca la escribas en un comando, en este archivo, en un `.md`, en un log,
  ni en un mensaje al usuario.
- Si el usuario pega la key en el chat, úsala solo para exportarla a la
  variable de entorno de la sesión — no la repitas de vuelta ni la dejes en
  ningún archivo versionado.
- Antes de generar, comprueba que la variable exista:
  ```bash
  test -n "$APIGEN_API_KEY" && echo "seteada" || echo "falta APIGEN_API_KEY"
  ```
  ```powershell
  if ($env:APIGEN_API_KEY) { "seteada" } else { "falta APIGEN_API_KEY" }
  ```
  Si falta, pide al usuario que la exporte y detente — no la pidas para
  escribirla tú en el comando.
- Si necesitas persistirla localmente entre sesiones, usa un `.env`
  **gitignored** (confirmar que `.env`/`.env.*` están en `.gitignore` antes
  de crear uno) — nunca un archivo versionado.
- El script wrapper (`scripts/apigen-api.sh` / `.ps1`) ya lee la variable
  directamente; no dupliques la key como argumento del script.

---

## Fase 1 — Resolver URL del endpoint

- **No hay endpoint default.** El wrapper no asume ninguna URL "conocida" —
  la URL de destino es **siempre obligatoria**, igual que `APIGEN_API_KEY`.
- Si el usuario da una URL desplegada, úsala: `--url <url>` (bash) /
  `-Url <url>` (PowerShell), o exportar `APIGEN_API_URL` antes de invocar.
- Si el usuario no da URL y `APIGEN_API_URL` no está seteada, **no
  inventes ni asumas un endpoint** — pídesela antes de ejecutar. El script
  falla con mensaje claro si llega a faltar de todos modos.

## Fase 2 — Preparar/validar el spec OpenAPI

Misma validación que la skill `apigen-cli` (Fase 2): revisar
`x-apigen-project`, `x-apigen-models`, `x-apigen-mapping`, `x-apigen-binding`
en el spec del usuario antes de llamar a la API. No inventar contenido sin
confirmar con el usuario. Si la skill `apigen-openapi-check` está instalada,
úsala primero.

## Fase 3 — Ejecutar generación vía API

1. Confirmar `APIGEN_API_KEY` seteada (ver arriba).
2. Confirmar URL de destino resuelta (Fase 1) — vía `APIGEN_API_URL` o
   `--url`/`-Url`. Sin ella, no ejecutes el wrapper: pídesela al usuario.
3. Ejecutar el wrapper (ruta según "Dónde viven los scripts de esta skill"):

   ```bash
   <ruta-a-esta-skill>/scripts/apigen-api.sh "<ruta-spec>" -o "<outdir>" --url "<url>" --unzip
   ```
   ```powershell
   <ruta-a-esta-skill>/scripts/apigen-api.ps1 -Spec "<ruta-spec>" -OutDir "<outdir>" -Url "<url>" -Unzip
   ```
4. El script:
   - valida que el spec exista,
   - valida que `APIGEN_API_KEY` esté seteada (falla con mensaje claro si no),
   - valida que la URL esté seteada, sin default (falla con mensaje claro si no),
   - crea `<outdir>` si no existe,
   - hace el POST multipart y guarda `<outdir>/<nombre-spec>.zip`,
   - con `--unzip`/`-Unzip`, descomprime en `<outdir>/<nombre-spec>/`.
5. Si el HTTP status no es 200, el script imprime el body de error
   (`ErrorsResponse`: `{"Errors":[{"message":...,"status":...}]}`) y termina
   con código distinto de cero — repórtalo al usuario, no asumas éxito.

## Fase 4 — Post-generación

Igual que `apigen-cli` Fase 4: si el spec usa `data-driver`
postgresql/mysql, recordar que el proyecto generado necesita `DATABASE_URL`
en runtime. Sugerir `dotnet build` para verificar que compila. No correr el
proyecto ni tocar bases reales sin pedirlo el usuario explícitamente.

---

## Notas

- Esta skill es el equivalente "remoto" de `apigen-cli` — mismo spec, misma
  arquitectura generada, distinto canal de invocación (HTTP en vez de
  binario local). Útil para pipelines CI/CD o entornos sin el CLI instalado.
- No hay endpoint de health/version documentado en esta skill — si se
  necesita comprobar disponibilidad del servicio antes de generar, usar el
  Swagger UI de la instancia (`<base-url>/swagger`) manualmente.
