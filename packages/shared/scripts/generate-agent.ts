// Writes the generated native agent constants. See agent-codegen.ts.

import { writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { renderAgentGeneratedDart } from './agent-codegen'

const target = resolve(
    import.meta.dirname,
    '../../../apps/native/lib/voice/agent_generated.dart',
)
writeFileSync(target, renderAgentGeneratedDart())
console.log(`wrote ${target}`)
