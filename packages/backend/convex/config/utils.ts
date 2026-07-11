// Semver comparison for client-version gating. Lenient by design: ignores
// build metadata ('1.0.0+7' → 1.0.0) and pre-release tags ('1.0.0-beta' →
// 1.0.0), comparing major.minor.patch only. Non-numeric segments count as 0.
const parseVersion = (raw: string): [number, number, number] => {
    const core = raw.split('+')[0].split('-')[0]
    const parts = core.split('.')
    const segment = (index: number): number => {
        const parsed = Number.parseInt(parts[index] ?? '0', 10)
        return Number.isFinite(parsed) ? parsed : 0
    }
    return [segment(0), segment(1), segment(2)]
}

// Returns -1 if a < b, 0 if equal, 1 if a > b.
export const compareVersions = (a: string, b: string): number => {
    const left = parseVersion(a)
    const right = parseVersion(b)
    for (let i = 0; i < 3; i++) {
        if (left[i] < right[i]) return -1
        if (left[i] > right[i]) return 1
    }
    return 0
}
