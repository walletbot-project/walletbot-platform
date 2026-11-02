import { execFileSync } from 'node:child_process'
import { mkdtempSync, readdirSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { basename, dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const diagramsDir = join(root, 'docs', 'diagrams')
const scale = Number(process.env.DIAGRAM_SCALE ?? 2)

const chromeCandidates = [
    process.env.CHROME_PATH,
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
    'google-chrome',
    'google-chrome-stable',
    'chromium',
    'chromium-browser',
].filter(Boolean)

const findChrome = () => {
    for (const candidate of chromeCandidates) {
        try {
            execFileSync(candidate, ['--version'], { stdio: 'ignore' })
            return candidate
        } catch {}
    }
    throw new Error(
        'Chrome or Chromium not found. Set CHROME_PATH to its executable.',
    )
}

const readSize = (svgPath) => {
    const svg = readFileSync(svgPath, 'utf8')
    const tag = svg.match(/<svg\b[^>]*>/)?.[0] ?? ''
    const width = Number(tag.match(/\bwidth="(\d+)"/)?.[1])
    const height = Number(tag.match(/\bheight="(\d+)"/)?.[1])
    if (!width || !height) {
        throw new Error(
            `${svgPath}: the root <svg> needs numeric width and height`,
        )
    }
    return { width, height }
}

const targets = process.argv.slice(2).length
    ? process.argv.slice(2).map((name) => resolve(diagramsDir, name))
    : readdirSync(diagramsDir)
          .filter((name) => name.endsWith('.svg'))
          .map((name) => join(diagramsDir, name))

const chrome = findChrome()

for (const svgPath of targets) {
    const { width, height } = readSize(svgPath)
    const pngPath = svgPath.replace(/\.svg$/, '.png')
    const profile = mkdtempSync(join(tmpdir(), 'render-diagrams-'))
    try {
        execFileSync(
            chrome,
            [
                '--headless',
                '--disable-gpu',
                '--hide-scrollbars',
                '--no-first-run',
                '--no-default-browser-check',
                `--user-data-dir=${profile}`,
                `--force-device-scale-factor=${scale}`,
                `--window-size=${width},${height}`,
                '--default-background-color=ffffffff',
                `--screenshot=${pngPath}`,
                pathToFileURL(svgPath).href,
            ],
            { stdio: 'ignore' },
        )
    } finally {
        rmSync(profile, { recursive: true, force: true })
    }
    console.log(
        `${basename(svgPath)} -> ${basename(pngPath)} (${width * scale}x${height * scale})`,
    )
}
