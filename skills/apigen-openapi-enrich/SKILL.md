---
name: apigen-openapi-enrich
description: >
  Agrega/corrige las extensiones x-apigen-* (x-apigen-project,
  x-apigen-models, x-apigen-mapping, x-apigen-binding) en un OpenAPI nuevo o
  incompleto para que apigen.net lo genere correctamente, traduciendo
  `type`/`format` estándar al vocabulario exacto de ApiGen y detectando
  entidades/relaciones a partir de los schemas y paths. Usar cuando el
  usuario pida "agrega las propiedades x-apigen a mi OpenAPI", "completa mi
  spec para apigen", "mi OpenAPI es nuevo, ayúdame a prepararlo", o quiera
  corregir los hallazgos que reportó la skill apigen-openapi-check.
---

# ApiGen OpenAPI Enrich Skill

Redacta y agrega las extensiones `x-apigen-*` que le faltan a un OpenAPI
para que `apigen.net` lo genere correctamente. Complementa a
`apigen-openapi-check` (que solo detecta huecos): esta skill **redacta el
contenido** y lo edita en el spec.

**Alcance explícito:** solo agrega/corrige extensiones. No instala ni
invoca el CLI/REST — remite a `apigen-cli` (CLI) o `apigen-api` (REST) una
vez el spec está listo. Al final de su flujo corre `apigen-openapi-check`
como verificación, no reinventa esas reglas.

---

## Tabla de vocabulario de tipos — única fuente de verdad

**`attributes[].type`** (case-insensitive, usar exactamente uno de estos —
cualquier otro valor produce un tipo C# inexistente que no compila):

| `type` ApiGen | Tipo C# resultante |
|---|---|
| `Integer` / `Long` / `Number` | `long?` |
| `Boolean` | `bool?` |
| `LocalDate` / `LocalDateTime` | `DateTime?` |
| `String` | `string?` |
| `Array` | `List<{items-type}>?` |
| `Relation` | `{items-type}?` |

**Importante — `x-apigen-models.attributes[].type` no tiene concepto de
`format`.** La traducción `type: String` + `format: date`/`date-time` →
`DateTime?` **solo aplica al DTO** (el schema estándar de
`components.schemas`, que sí tiene `format`) — la función que traduce
`x-apigen-models.attributes[].type` (`FormatTypeEntity`) nunca recibe
`format`, así que un atributo de fecha en una entidad debe declararse
**explícitamente** como `type: LocalDate` o `type: LocalDateTime`, nunca
`type: String` aunque el campo equivalente en el DTO tenga
`format: date-time` — usar `String` ahí generará `string?` en la entidad en
vez de `DateTime?`, silenciosamente.

**`attributes[].items-type`** — **no** usa este vocabulario, es un **token
C# literal** sustituido tal cual:
- Array de escalares → nombre de tipo C# real: `string`, `long`, `bool`,
  `DateTime` (nunca `String`/`Integer`/etc.).
- `Array`/`Relation` de una entidad relacionada → el **nombre exacto
  (case-sensitive) de la clave de esa entidad** en `x-apigen-models` — no se
  Pascaliza automáticamente en este punto, debe coincidir literalmente.

**Regla de nombres de entidad:** decide el nombre de cada entidad ya en
PascalCase singular (ej. `Pet`, no `pet` ni `Pets`) y **reusa ese mismo
string literal** en `x-apigen-models` (clave), `x-apigen-binding.model`,
`x-apigen-mapping.model` e `items-type` de relaciones. No lo varíes de un
lugar a otro — varias partes del generador comparan el string tal cual, no
Pascalizado.

---

## Procedimiento

### 1. Leer el spec del usuario

Revisar `components.schemas` y `paths`. Si ya tiene algo de `x-apigen-*`, no
lo pises sin confirmar con el usuario primero.

### 2. Verificar/agregar `operationId` en cada operación — antes que nada

**Esto no es una extensión `x-apigen-*`, es un campo OpenAPI estándar, pero
es obligatorio para ApiGen y se confirmó rompiendo el generador
directamente**: sin `operationId`, `ControllersGenerator` truena con
`ArgumentNullException` en `Humanizer.Pascalize` al generar el controller —
no es una degradación silenciosa, es un crash duro. Muchos editores no lo
marcan como obligatorio, así que es fácil que un spec nuevo no lo tenga.

Antes de tocar cualquier extensión `x-apigen-*`, recorre **todas** las
operaciones (`get`/`post`/`put`/`patch`/`delete`/etc. de cada path) y
propone un `operationId` único y descriptivo si falta (ej. `getBooks`,
`createBook`, `getBookById`) — camelCase, verbo + recurso, sin espacios.

### 3. Declarar cada tag usado en el arreglo `tags:` de la raíz — antes de seguir

**Otro campo OpenAPI estándar (no `x-apigen-*`) crítico, confirmado
generando y corriendo el proyecto real, no solo leyendo código:** si dos o
más operaciones comparten un tag (ej. `tags: [books]`) y ese nombre **no**
está declarado en el arreglo `tags:` de la raíz del documento, el lector de
OpenAPI crea un objeto de tag distinto por operación aunque el nombre sea
igual. `ControllersGenerator` compara tags por referencia de objeto, no por
nombre — resultado: **solo sobrevive una de esas operaciones en el
controller generado, las demás desaparecen en silencio** (sin error de
generación ni de compilación, el proyecto compila igual pero le faltan
endpoints).

Antes de proponer `x-apigen-binding`, recorre todos los `tags: [...]` usados
en las operaciones y agrega uno por cada nombre distinto al arreglo raíz:
```yaml
tags:
  - name: books
```
Si el spec del usuario ya tiene paths con el mismo tag repetido en varias
operaciones y **no** tiene este arreglo raíz, trátalo como hallazgo crítico
igual de urgente que un `x-apigen-models` faltante — no es opcional aunque
técnicamente el spec sea válido sin él.

### 4. Proponer `x-apigen-models` por cada entidad persistida

**Ubicación obligatoria: bajo `components`, no en la raíz del documento**
(`components.x-apigen-models`, hermano de `components.schemas`) —
confirmado con `apigen-openapi-check`: puesto en la raíz, el checker lo
reporta como "ausente o vacio bajo 'components'" y el generador crea una
entidad placeholder `Sample` en vez de las reales.
```yaml
components:
  x-apigen-models:
    Pet:
      attributes: { ... }
  schemas:
    PetDto: { ... }
```

Uno o más schemas pueden mapear a la misma entidad (ej. `Pet`, `PetGet`,
`PetPost` → todos a la entidad `Pet`) — identifica el conjunto y una sola
clave de entidad para todos.

Por cada propiedad del schema:
- Traducir `type`/`format` de OpenAPI al vocabulario de la tabla de arriba.
- **Primary key:** heurística — propiedad `id`, o `format: uuid`. Si es
  ambiguo, pregunta al usuario en vez de adivinar. Marcar con
  `relational-persistence.primary-key: true`.
- **Relaciones** (`$ref` a otro schema, o array de otro schema): usar
  `type: Relation` (uno) o `type: Array` (muchos) + `items-type:
  <NombreExactoEntidad>`. Para que sea una FK real (no solo navegación),
  agregar `relational-persistence.column` con un nombre **distinto** al de
  la propiedad (ej. propiedad `owner` → columna `owner_id`) — si el nombre
  de columna coincide con el de la propiedad, el generador no la trata como
  FK.
  - **Límite conocido del generador — avisar, no intentar compensar:** la
    columna FK escalar que el generador crea para una relación siempre
    termina tipada `long?`, sin importar el tipo real de la primary key de
    la entidad referenciada (bug de resolución interno). Si la entidad
    referenciada tiene una PK que no es numérica (ej. `uuid`/`string`),
    avisa esto explícitamente al usuario — no hay combinación de
    propiedades en el OpenAPI que lo corrija, el generador necesitaría un
    fix de código.
- **Validaciones** — usar keywords OpenAPI estándar, nunca la clave
  `x-apigen-models.attributes[].validations` (decorativa, el generador no
  la lee):
  - `[StringLength]` sale de `minLength` **y** `maxLength` juntos (ambos o
    ninguno — uno solo no activa nada).
  - `[Range]` sale de `minimum` **y** `maximum` juntos (mismo caso).
  - `format: date-time` en un `string` → `DataType.DateTime`; cualquier
    otro `format` en un string cae igual a `DataType.Date` (no hay mapeo
    real para `email`/`uuid`/etc. — no prometas ese comportamiento).
  - `pattern` nunca se lee, no lo sugieras como si tuviera efecto.
- `relational-persistence.table` es opcional — si se omite, EF Core usa el
  nombre de la clase/entidad como tabla por defecto. Solo agrégalo si el
  usuario quiere un nombre de tabla distinto (ej. snake_case explícito).

### 5. Proponer `x-apigen-mapping` por cada DTO

Para cada schema usado como request/response body en algún path:
```yaml
components:
  schemas:
    PetDto:
      x-apigen-mapping:
        model: Pet
```

### 6. Proponer `x-apigen-binding` por cada path del recurso

`x-apigen-binding` solo necesita estar en un path por grupo de tag para que
el controller se genere, pero si dos paths del mismo tag declararan modelos
distintos, solo gana el primero que aparezca en el documento para *todas*
las operaciones — para evitar ese riesgo, **aplícalo a todos los paths del
mismo recurso**, no solo a uno:
```yaml
paths:
  /pets:
    x-apigen-binding: { model: Pet }
  /pets/{id}:
    x-apigen-binding: { model: Pet }
```

### 7. Proponer `x-apigen-project`

Preguntar al usuario si necesita PostgreSQL/MySQL o si in-memory está bien:
```yaml
x-apigen-project:
  data-driver: postgresql   # o mysql / omitir para in-memory
```
**No agregues** `name`/`description`/`version` — son decorativos,
confirmados como nunca leídos por el generador (`apigen-openapi-check` ya
los marca así). Si el usuario insiste en tenerlos, acláraselo antes de
agregarlos.

### 8. Confirmar antes de editar

Presenta el resumen completo de lo que se va a agregar (todas las
entidades/mappings/bindings juntos, no campo por campo) y pide **una** sola
confirmación antes de tocar el archivo del usuario.

### 9. Aplicar y verificar

Aplica los cambios con `Edit`. Luego corre la skill/script de validación
sobre el resultado — el validador vive en la skill `apigen-openapi-check`
(carpeta hermana `../apigen-openapi-check/scripts/`):
```bash
../apigen-openapi-check/scripts/apigen-openapi-check.sh "<ruta-spec>"
```
```powershell
../apigen-openapi-check/scripts/apigen-openapi-check.ps1 -Spec "<ruta-spec>"
```
Si no conocés la ruta exacta donde quedaron instaladas ambas skills, ubicá
el script con `find . -path '*apigen-openapi-check/scripts/apigen-openapi-check.sh'`
(Unix) o `Get-ChildItem -Recurse -Filter apigen-openapi-check.ps1` (Windows).

Reporta al usuario si quedó limpio (0 críticos) o si algo requiere otra
vuelta. Solo entonces sugiere continuar con `apigen-cli` / `apigen-api` para
generar el proyecto.
