---
name: apigen-cli
description: >
  Instala y ejecuta el CLI `apigen` de este repo para generar un proyecto .NET
  (arquitectura hexagonal: Api/Domain/Infrastructure + tests) a partir de una
  definición OpenAPI. Ayuda a preparar/validar las extensiones x-apigen-project,
  x-apigen-models, x-apigen-mapping y x-apigen-binding en el spec antes de generar,
  resuelve la instalación global del tool (instalador oficial install.sh/.ps1,
  binario self-contained sin requerir .NET, o dotnet tool install si ya hay SDK
  instalado, con fallback a build+pack local si el paquete no está publicado en
  NuGet), ejecuta
  `apigen <spec> -o <dir>` y descomprime el resultado. Usar cuando el usuario pida
  "genera el proyecto con apigen", "usa el CLI para generar la API", "instala el
  CLI apigen", "genera código desde mi OpenAPI", o similar.
---

# Apigen CLI Skill

Automatiza instalación + uso del CLI `apigen` (proyecto `src/Command`, paquete
`ApiAddicts.Apigen`, comando global `apigen`) para generar un proyecto .NET
hexagonal a partir de un spec OpenAPI.

Comando final del CLI (sin subcomandos):
```
apigen <ruta-openapi.yml|yaml|json> [-o|--outpath <dir>]
```
- Arg posicional = ruta al spec (YAML o JSON, autodetectado). Si se omite, genera
  un proyecto "template" stub.
- `-o`/`--outpath` = carpeta de salida del `.zip` generado (default: directorio del
  propio ejecutable — **siempre pasar `-o` explícito**, no confiar en el default).
- Nombre del proyecto generado = `info.title` del spec (PascalCase, sin espacios/guiones).
  No es un flag.
- Target framework generado: fijo en `net10.0`.

---

## Fase 1 — Asegurar instalación global de `apigen`

Dos familias de instalación, en orden de preferencia. La vía NuGet
(`dotnet tool install`) **requiere tener el SDK de .NET instalado** — si
no está, o no se quiere depender de él, usar directamente la vía del
instalador oficial (binario self-contained, no necesita .NET para nada).

1. Detectar si ya está instalado, en el PATH:
   ```powershell
   Get-Command apigen -ErrorAction SilentlyContinue
   ```
   Si existe, saltar a Fase 2.

2. Si no está en el PATH, comprobar si ya está instalado en la ruta
   default del instalador oficial (puede no haberse recargado el PATH de
   esta sesión):
   - Windows: `"$env:LOCALAPPDATA\apigen\bin\apigen.exe"`
   - Linux/macOS: `"$HOME/.apigen/bin/apigen"`
   Si existe ahí, invocarlo por ruta absoluta en esta sesión (no depender
   de que el PATH ya esté recargado).

3. Si no existe en ningún lado, elegir vía de instalación:

   **Vía A — instalador oficial (recomendada, no requiere .NET instalado):**
   binario self-contained, lleva el runtime embebido.
   ```powershell
   irm https://raw.githubusercontent.com/apiaddicts/apigen.net/main/install.ps1 | iex
   ```
   ```bash
   curl -fsSL https://raw.githubusercontent.com/apiaddicts/apigen.net/main/install.sh | sh
   ```
   Instala en la ruta default del paso 2. En Windows, el instalador agrega
   la carpeta al PATH de usuario pero **requiere reiniciar la terminal**
   para que se recargue — dentro de la misma sesión, invocar por ruta
   absoluta.

   **Vía B — `dotnet tool` (solo si ya hay SDK de .NET instalado):**
   ```powershell
   dotnet tool install -g ApiAddicts.Apigen
   ```
   **Nota**: el repo no tiene workflow de CI/publish confirmado — este
   paquete puede no estar publicado. Si el comando falla (`NU1101`/`not
   found` o similar), o si directamente no hay `dotnet` disponible, no
   reintentar en loop — usar la Vía A, o el fallback de build+pack local:
   ```powershell
   dotnet pack ./src/Command/Command.csproj -c Release -o ./nupkg
   dotnet tool install -g --add-source ./nupkg ApiAddicts.Apigen
   ```
   Si ya estaba instalado desde un `./nupkg` anterior (versión distinta),
   usar `dotnet tool update -g --add-source ./nupkg ApiAddicts.Apigen` en
   vez de `install`. Este fallback también requiere `dotnet` — si no está
   disponible, la única vía viable es la A.

4. Verificar instalación:
   ```powershell
   Get-Command apigen
   ```
   (o `command -v apigen` / ruta absoluta si el PATH de la sesión no se
   recargó). Confirmar al usuario que quedó disponible. Nota informativa
   (no bloqueante): el banner de versión que imprime el CLI viene de
   `Directory.Build.props` (`1.0.1`), que puede no coincidir con el badge
   del README (`1.0.0`) — es un desfase conocido del repo, no un error de
   la skill.

---

## Fase 2 — Preparar/validar el spec OpenAPI

Localizar el archivo OpenAPI que el usuario quiere usar (o usar uno de
`src/Generator/Examples/*.yml|json` como referencia/prueba: `api-example.yml`,
`api-hospital.yml`, `petstore.json`, `Petstore with Owners-enriched.yaml` — ojo,
este último tiene espacios en el nombre, hay que citarlo entre comillas).

No hay archivo de config separado: toda la configuración vive como extensiones
`x-apigen-*` dentro del propio spec. Revisar el spec del usuario y señalar (sin
inventar contenido sin confirmar con el usuario) lo que falte:

### `x-apigen-project` (nivel documento raíz)
Metadata del proyecto + driver de base de datos.
```yaml
x-apigen-project:
  name: My Project
  description: Descripción del proyecto
  version: 1.0.0
  data-driver: postgresql   # postgresql | mysql | (omitir = in-memory)
```
Si falta, es el primero que hay que agregar — sin él, el proyecto igual genera
pero sin metadata explícita ni driver de persistencia definido.

### `x-apigen-models` (nivel components, junto a los schemas)
Define entidades y su mapeo relacional.
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
Revisar que cada entidad que deba persistirse tenga esto definido, especialmente
la primary key (`primary-key: true`).

### `x-apigen-mapping` (nivel schema, en el DTO)
Liga un DTO (schema usado en request/response) con una entidad de `x-apigen-models`.
```yaml
components:
  schemas:
    userDataSchema:
      x-apigen-mapping:
        model: User
      type: object
      properties: ...
```
Revisar que cada DTO expuesto en la API tenga esta liga apuntando a un `model`
que exista en `x-apigen-models`.

### `x-apigen-binding` (nivel path)
Liga un grupo de endpoints a un modelo (controla el controller/servicio generado).
```yaml
paths:
  /users:
    x-apigen-binding:
      model: User
```
Revisar que cada path relevante lo tenga.

### Conexión a base de datos
No es parte del spec ni del CLI — si `data-driver` no es in-memory, la connection
string se lee en runtime del proyecto generado vía env var `DATABASE_URL`. Solo
informar esto al usuario, no configurarlo en esta fase.

Al detectar huecos: mostrar el snippet exacto a agregar (basado en los ejemplos
de arriba) y pedir confirmación antes de editar el spec del usuario.

---

## Fase 3 — Ejecutar generación

1. Confirmar/crear carpeta de salida explícita:
   ```powershell
   New-Item -ItemType Directory -Force -Path <outdir>
   ```
2. Ejecutar:
   ```powershell
   apigen "<ruta-spec>" -o "<outdir>"
   ```
3. Revisar la salida de consola (Serilog) por warnings de diagnóstico del parser
   OpenAPI. Si algo se ve sospechoso, también hay log rotativo en:
   `<carpeta-del-ejecutable>\Logs\Apigen_Dotnet_{version}_.txt`
   (ubicar la carpeta del ejecutable con `(Get-Command apigen).Source`, buscar
   `Logs` junto al `.dll`/tool real si se necesita más detalle).
4. El CLI deja un `.zip` en `<outdir>` llamado `<nombre-archivo-sin-extension>.zip`
   (o `template.zip` si no se pasó spec). Descomprimir:
   ```powershell
   Expand-Archive -Path "<outdir>\<nombre>.zip" -DestinationPath "<outdir>\<nombre>" -Force
   ```

---

## Fase 4 — Post-generación

- Recordar al usuario: si usó `data-driver: postgresql|mysql`, debe setear
  `DATABASE_URL` como variable de entorno antes de correr el proyecto generado.
- Sugerir verificar que compila:
  ```powershell
  dotnet build "<outdir>\<nombre>\<nombre>.sln"
  ```
- No ejecutar `dotnet run` del proyecto generado ni tocar bases de datos reales
  sin que el usuario lo pida explícitamente.
