// Renders apps/native/lib/voice/agent_generated.dart from the shared agent
// sources — one mechanism keeping native in lockstep with the backend mint:
//
//   1. kAgentToolNames  — the tool manifest (backs the executor-parity test),
//   2. kAgentModel / kAgentVoiceName — the Live session constants,
//   3. kAgentContext*Cap — the mint context payload caps (native builds the
//      same payload the server validates),
//   4. kAgentSkills — the bundled skill bodies `readSkill` serves offline,
//   5. kAttachment*, the attachment types and limits the chat accepts.
//
// Run `pnpm run generate:agent` (in packages/shared) after changing any of
// the imported sources. `test/agent-codegen.test.ts` fails when the generated
// file on disk is stale.

import { AGENT_SKILLS } from '../src/agent-skills'
import {
    ATTACHMENT_IMAGE_MAX_DIMENSION,
    ATTACHMENT_MAX_BYTES,
    ATTACHMENT_MAX_NAME_LENGTH,
    ATTACHMENT_MAX_PER_MESSAGE,
    ATTACHMENT_TYPES,
} from '../src/attachments'
import { AGENT_MODEL, AGENT_VOICE_NAME, TOOL_NAMES } from '../src/tools'
import { AGENT_CONTEXT_CAPS } from '../src/tools/context'

function dartString(value: string): string {
    return `'${value.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$').replace(/\n/g, '\\n')}'`
}

export function renderAgentGeneratedDart(): string {
    // The emitted layout must be `dart format`-stable (format-on-save and CI
    // both run it over lib/): long AgentSkill bodies are emitted pre-wrapped
    // the way dart format wraps them.
    const lines: string[] = []
    lines.push('// GENERATED FILE — DO NOT EDIT.')
    lines.push('//')
    lines.push(
        '// Source: packages/shared (tools/constants.ts, tools/definitions.ts).',
    )
    lines.push(
        '// Regenerate with `pnpm run generate:agent` from packages/shared.',
    )
    lines.push(
        '// The freshness test lives at packages/shared/test/agent-codegen.test.ts.',
    )
    lines.push('')
    lines.push('/// The Gemini Live model the backend mints tokens for.')
    lines.push(`const String kAgentModel = ${dartString(AGENT_MODEL)};`)
    lines.push('')
    lines.push('/// The prebuilt voice negotiated into the session.')
    lines.push(
        `const String kAgentVoiceName = ${dartString(AGENT_VOICE_NAME)};`,
    )
    lines.push('')
    lines.push(
        '/// Every tool the token declares, in declaration order. The native',
    )
    lines.push(
        '/// executor switch must cover exactly this set (tool_manifest_test.dart).',
    )
    lines.push('const List<String> kAgentToolNames = [')
    for (const name of TOOL_NAMES) {
        lines.push(`  ${dartString(name)},`)
    }
    lines.push('];')
    lines.push('')
    lines.push(
        '/// Per-list caps of the mint context payload (abuse prevention;',
    )
    lines.push('/// enforced server-side by sanitizeAgentContext).')
    lines.push(
        `const int kAgentContextAccountsCap = ${AGENT_CONTEXT_CAPS.accounts};`,
    )
    lines.push(
        `const int kAgentContextCategoriesCap = ${AGENT_CONTEXT_CAPS.categories};`,
    )
    lines.push(`const int kAgentContextTagsCap = ${AGENT_CONTEXT_CAPS.tags};`)
    lines.push(
        `const int kAgentContextRecentTransactionsCap = ${AGENT_CONTEXT_CAPS.recentTransactions};`,
    )
    lines.push(
        `const int kAgentContextMemoriesCap = ${AGENT_CONTEXT_CAPS.memories};`,
    )
    lines.push('')
    lines.push(
        '/// Files the agent chat accepts (packages/shared/src/attachments.ts).',
    )
    lines.push('/// The server enforces the same limits on the stored file.')
    lines.push(
        `const int kAttachmentMaxPerMessage = ${ATTACHMENT_MAX_PER_MESSAGE};`,
    )
    lines.push(
        `const int kAttachmentImageMaxDimension = ${ATTACHMENT_IMAGE_MAX_DIMENSION};`,
    )
    lines.push(
        `const int kAttachmentMaxNameLength = ${ATTACHMENT_MAX_NAME_LENGTH};`,
    )
    lines.push('')
    lines.push('class AttachmentType {')
    lines.push('  const AttachmentType({')
    lines.push('    required this.mimeType,')
    lines.push('    required this.kind,')
    lines.push('    required this.extensions,')
    lines.push('    required this.maxBytes,')
    lines.push('  });')
    lines.push('')
    lines.push('  final String mimeType;')
    lines.push('  final String kind;')
    lines.push('  final List<String> extensions;')
    lines.push('  final int maxBytes;')
    lines.push('}')
    lines.push('')
    lines.push('const List<AttachmentType> kAttachmentTypes = [')
    for (const type of ATTACHMENT_TYPES) {
        const mimeLine = `    mimeType: ${dartString(type.mimeType)},`
        lines.push('  AttachmentType(')
        if (mimeLine.length > 80) {
            lines.push('    mimeType:')
            lines.push(`        ${dartString(type.mimeType)},`)
        } else {
            lines.push(mimeLine)
        }
        lines.push(`    kind: ${dartString(type.kind)},`)
        lines.push(
            `    extensions: [${type.extensions.map(dartString).join(', ')}],`,
        )
        lines.push(`    maxBytes: ${ATTACHMENT_MAX_BYTES[type.kind]},`)
        lines.push('  ),')
    }
    lines.push('];')
    lines.push('')
    lines.push(
        '/// A bundled agent skill — see packages/shared/src/agent-skills.',
    )
    lines.push('class AgentSkill {')
    lines.push('  const AgentSkill({')
    lines.push('    required this.slug,')
    lines.push('    required this.title,')
    lines.push('    required this.body,')
    lines.push('  });')
    lines.push('')
    lines.push('  final String slug;')
    lines.push('  final String title;')
    lines.push('  final String body;')
    lines.push('}')
    lines.push('')
    lines.push(
        '/// The reference documents the `readSkill` tool serves, offline.',
    )
    lines.push('const List<AgentSkill> kAgentSkills = [')
    for (const skill of AGENT_SKILLS) {
        lines.push('  AgentSkill(')
        lines.push(`    slug: ${dartString(skill.slug)},`)
        lines.push(`    title: ${dartString(skill.title)},`)
        lines.push('    body:')
        lines.push(`        ${dartString(skill.body)},`)
        lines.push('  ),')
    }
    lines.push('];')
    lines.push('')
    return lines.join('\n')
}
