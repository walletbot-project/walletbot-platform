import { defineCollection } from 'astro:content'
import { glob } from 'astro/loaders'

// The legal documents are maintained in `docs/legal` at the repo root (its
// README owns the update rules — ES and EN must always change together).
// Loading them from there instead of copying keeps the landing rendering the
// exact operative files. They have no frontmatter, so the collection is
// schema-less.
const legal = defineCollection({
    loader: glob({
        pattern: ['privacy-policy.*.md', 'terms-and-conditions.*.md'],
        base: '../../docs/legal',
        // The default id generator slugifies away the `.en`/`.es` dot. Keep the
        // filename stem instead, so ids stay `privacy-policy.en` etc. and pages
        // can address them as `${doc}.${locale}`.
        generateId: ({ entry }) => entry.replace(/\.md$/, ''),
    }),
})

export const collections = { legal }
