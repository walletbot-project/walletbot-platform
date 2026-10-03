#!/usr/bin/env node

/**
 * Valida los dashboards de Grafana versionados en `docs/dashboards/`.
 *
 * Existe por un bug real: una fila era `AutoGridLayout` y se le agregaron
 * items `GridLayoutItem` con coordenadas. Grafana rechaza el import con
 * `Value must be "AutoGridLayoutItem"` sin decir en que fila, y el JSON
 * parsea perfecto, asi que nada lo detecta antes de subirlo a mano.
 *
 * Chequea lo que Grafana no perdona y lo que se rompe en silencio:
 *
 * - el tipo de item tiene que coincidir con el tipo de layout de su fila;
 * - un `GridLayoutItem` necesita x/y/width/height, un `AutoGridLayoutItem` no
 *   los lleva;
 * - la grilla es de 24 columnas y `x + width` no puede pasarse;
 * - dos paneles no pueden ocupar la misma celda (se renderizan uno encima del
 *   otro, sin ningun error);
 * - un panel definido en `elements` pero no puesto en ningun layout no se ve;
 * - una fila referencia paneles que existen, y ningun panel queda sin query.
 *
 * Uso: `pnpm run validate-dashboards`
 */

import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

const DASHBOARDS_DIR = 'docs/dashboards'
const GRID_COLUMNS = 24

/**
 * Cada tipo de layout acepta un solo tipo de item, con sus propias claves
 * obligatorias. Mezclarlos es lo que Grafana rechaza al importar.
 */
const LAYOUTS = {
    GridLayout: {
        item: 'GridLayoutItem',
        required: ['element', 'x', 'y', 'width', 'height'],
        positioned: true,
    },
    AutoGridLayout: {
        item: 'AutoGridLayoutItem',
        required: ['element'],
        positioned: false,
    },
}

/** @param {string} dir */
function dashboardFiles(dir) {
    try {
        return readdirSync(dir)
            .filter((name) => name.endsWith('.json'))
            .sort()
            .map((name) => join(dir, name))
    } catch (error) {
        if (error.code === 'ENOENT') return []
        throw error
    }
}

/**
 * @param {Record<string, unknown>} doc
 * @returns {string[]}
 */
function validate(doc) {
    const errors = []
    const spec = doc.spec
    if (!spec) return ['sin `spec` en la raiz: no parece un dashboard v2']

    const elements = spec.elements ?? {}
    const rows = spec.layout?.spec?.rows
    if (!Array.isArray(rows)) return ['`spec.layout.spec.rows` no es una lista']

    const referenced = new Set()

    rows.forEach((row, index) => {
        const rowSpec = row.spec ?? {}
        const where = `fila ${index} (${JSON.stringify(rowSpec.title ?? null)})`
        const layout = rowSpec.layout
        const rules = LAYOUTS[layout?.kind]

        if (!rules) {
            errors.push(`${where}: layout desconocido ${layout?.kind}`)
            return
        }

        // `GridLayout.spec` solo lleva `items`. Los campos de AutoGridLayout
        // (maxColumnCount, rowHeightMode, columnWidthMode) sobran ahi, y
        // quedarse uno pegado al convertir una fila es facil.
        if (rules.positioned) {
            const extra = Object.keys(layout.spec).filter((k) => k !== 'items')
            if (extra.length > 0) {
                errors.push(
                    `${where}: GridLayout no acepta ${extra.join(', ')}`,
                )
            }
        }

        /** @type {Map<string, string>} */
        const occupied = new Map()

        for (const item of layout.spec.items ?? []) {
            if (item.kind !== rules.item) {
                errors.push(
                    `${where}: ${layout.kind} lleva ${rules.item}, ` +
                        `encontrado ${item.kind}`,
                )
                continue
            }

            const missing = rules.required.filter((key) => !(key in item.spec))
            if (missing.length > 0) {
                errors.push(`${where}: item sin ${missing.join(', ')}`)
                continue
            }

            const name = item.spec.element?.name
            referenced.add(name)
            if (!(name in elements)) {
                errors.push(`${where}: referencia al panel inexistente ${name}`)
            }

            if (!rules.positioned) continue

            const { x, y, width, height } = item.spec
            if (x + width > GRID_COLUMNS) {
                errors.push(
                    `${where}/${name}: se pasa de la grilla de ` +
                        `${GRID_COLUMNS} (x=${x} + width=${width})`,
                )
            }

            for (let dx = x; dx < x + width; dx += 1) {
                for (let dy = y; dy < y + height; dy += 1) {
                    const cell = `${dx},${dy}`
                    const clash = occupied.get(cell)
                    if (clash && clash !== name) {
                        errors.push(
                            `${where}: ${name} se solapa con ${clash} ` +
                                `en (${cell})`,
                        )
                    }
                    occupied.set(cell, name)
                }
            }
        }
    })

    const orphans = Object.keys(elements)
        .filter((name) => !referenced.has(name))
        .sort()
    if (orphans.length > 0) {
        errors.push(
            `paneles definidos pero no puestos en ningun layout: ` +
                orphans.join(', '),
        )
    }

    for (const [name, element] of Object.entries(elements)) {
        const queries = element.spec?.data?.spec?.queries ?? []
        if (queries.length === 0) {
            errors.push(`${name}: sin ninguna query`)
            continue
        }
        for (const query of queries) {
            if (!query.spec?.query?.spec?.expr?.trim()) {
                errors.push(`${name}: query vacia`)
            }
        }
    }

    return errors
}

const files = dashboardFiles(DASHBOARDS_DIR)
if (files.length === 0) {
    console.error(`No hay dashboards en ${DASHBOARDS_DIR}/`)
    process.exit(1)
}

let failed = false
for (const file of files) {
    let doc
    try {
        doc = JSON.parse(readFileSync(file, 'utf8'))
    } catch (error) {
        console.error(`✗ ${file}: JSON invalido — ${error.message}`)
        failed = true
        continue
    }

    const errors = validate(doc)
    if (errors.length > 0) {
        failed = true
        console.error(`✗ ${file}: ${errors.length} problema(s)`)
        for (const error of errors) console.error(`    - ${error}`)
        continue
    }

    const rows = doc.spec.layout.spec.rows.length
    const panels = Object.keys(doc.spec.elements).length
    console.log(`✓ ${file}: ${rows} filas, ${panels} paneles`)
}

process.exit(failed ? 1 : 0)
