# Dashboards de Grafana versionados

Los dashboards viven como JSON en `docs/dashboards/`. No se despliegan con el
backend: se importan a mano desde Grafana.

## Importar

**Dashboards → New → Import → Upload JSON file.**

⚠️ `metadata.name` es el identificador: importar un JSON con el mismo
`metadata.name` **pisa el dashboard existente**. Para probar sin tocar el
vigente, cambiá ese campo antes de subirlo (`geb465q` → `geb465q-test`).

Después de importar, revisá el selector **`$Scope`** — ver
[promql.md](./promql.md#scope).

## El esquema v2, y su trampa de layout

`apiVersion: dashboard.grafana.app/v2`. Dos secciones que hay que mantener en
sincronía a mano:

- **`spec.elements`** — los paneles, cada uno con su `id`, `title`, queries y
  `vizConfig`. Es un objeto indexado por nombre (`panel-14`), no una lista.
- **`spec.layout`** — dónde va cada panel. `RowsLayout` con filas, y cada fila
  tiene su propio layout adentro.

**Un panel definido en `elements` pero no referenciado desde `layout` no se ve,
y Grafana no se queja.**

### GridLayout vs AutoGridLayout

Cada fila usa uno de los dos, y **cada uno acepta un solo tipo de item**:

| Layout de la fila | Item | Coordenadas |
|---|---|---|
| `GridLayout` | `GridLayoutItem` | `x`, `y`, `width`, `height` obligatorios |
| `AutoGridLayout` | `AutoGridLayoutItem` | ninguna: Grafana acomoda solo |

Mezclarlos hace que el import falle con:

```
Value must be "AutoGridLayoutItem"
```

...sin decir en qué fila. Y el JSON parsea perfecto, así que nada lo detecta
antes de subirlo.

**Cómo se cuela:** una fila `AutoGridLayout` con un solo panel tiene un item sin
`x`/`y`/`width`/`height`. Es idéntico a un `GridLayoutItem` al que le faltan las
coordenadas. Si asumís lo segundo y agregás items posicionados, la fila queda
rota. Pasó exactamente así el 2026-09-10.

Otras dos cosas que importan:

- `GridLayout.spec` solo lleva `items`. Los campos de `AutoGridLayout`
  (`maxColumnCount`, `rowHeightMode`, `columnWidthMode`) sobran ahí, y es fácil
  que quede uno pegado al convertir una fila de un tipo al otro.
- La grilla es de **24 columnas**. `x + width > 24` se desborda, y **dos paneles
  sobre la misma celda se renderizan uno encima del otro sin ningún error**.

## El validador

```sh
pnpm run validate-dashboards
```

`scripts/validate-dashboards.mjs`. Existe por el bug de arriba. Chequea:

- el tipo de item coincide con el tipo de layout de su fila;
- `GridLayoutItem` trae las cuatro coordenadas y `AutoGridLayoutItem` no;
- `GridLayout.spec` no arrastra campos de `AutoGridLayout`;
- `x + width` no se pasa de 24;
- ningún par de paneles se solapa;
- ningún panel queda fuera de todos los layouts;
- ninguna referencia apunta a un panel inexistente;
- ningún panel queda sin query.

Corre en el workflow de `lint`, que hoy dispara **solo en PRs contra `main`**:
un PR apilado sobre otra rama no lo ejecuta. Corrélo a mano en ese caso.

## Editar el JSON

Es de 100 KB y está muy anidado; editarlo a mano es propenso a error. El patrón
que funcionó: un script de Python que carga el JSON, modifica lo que
corresponde y lo vuelve a escribir con `indent=4` (el estilo del archivo, que
biome después confirma), seguido de `pnpm run validate-dashboards`.

Al terminar, si hay una copia de trabajo afuera del repo (por ejemplo en el
Escritorio para importar sin sacar el worktree), **actualizala también** — es
fácil terminar importando una versión vieja.
