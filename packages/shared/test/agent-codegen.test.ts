import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { renderAgentGeneratedDart } from '../scripts/agent-codegen'

describe('agent codegen', () => {
    it('apps/native/lib/voice/agent_generated.dart is up to date', () => {
        const target = resolve(
            import.meta.dirname,
            '../../../apps/native/lib/voice/agent_generated.dart',
        )
        const onDisk = readFileSync(target, 'utf8')
        expect(onDisk).toBe(renderAgentGeneratedDart())
    })
})
