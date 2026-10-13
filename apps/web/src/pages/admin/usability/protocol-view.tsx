import type { UsabilityMaterial } from '@wallet-bot/shared'
import { type ReactNode, useState } from 'react'
import { Icon } from '@/components/m3/icon'
import { useT } from '@/lib/i18n'
import { cn } from '@/lib/utils'

export function Surface({
    children,
    className,
}: {
    children: ReactNode
    className?: string
}) {
    return (
        <section
            className={cn(
                'flex flex-col gap-3 rounded-3xl bg-surface-container-high p-4 text-on-surface',
                className,
            )}
        >
            {children}
        </section>
    )
}

export function SectionTitle({ children }: { children: ReactNode }) {
    return <h2 className="m3-title-medium text-on-surface">{children}</h2>
}

export function SayBlock({
    title,
    paragraphs,
}: {
    title?: string
    paragraphs: readonly string[]
}) {
    const t = useT()
    return (
        <section className="flex flex-col gap-3 rounded-3xl border-l-4 border-tertiary bg-tertiary-container/40 p-4">
            <span className="m3-label-large flex items-center gap-2 text-on-surface-variant">
                <Icon name="record_voice_over" size={18} />
                {title ?? t.usability.readAloud}
            </span>
            {paragraphs.map((paragraph) => (
                <p key={paragraph} className="m3-body-large text-on-surface">
                    {paragraph}
                </p>
            ))}
        </section>
    )
}

export function NoteBlock({ text }: { text: string }) {
    return (
        <p className="m3-body-medium flex gap-2 px-1 text-on-surface-variant">
            <Icon name="info" size={20} className="shrink-0" />
            <span>{text}</span>
        </p>
    )
}

export function ListBlock({
    title,
    items,
}: {
    title: string
    items: readonly string[]
}) {
    return (
        <Surface>
            <SectionTitle>{title}</SectionTitle>
            <ul className="m3-body-medium flex list-disc flex-col gap-2 pl-5">
                {items.map((item) => (
                    <li key={item}>{item}</li>
                ))}
            </ul>
        </Surface>
    )
}

export function MaterialView({ material }: { material: UsabilityMaterial }) {
    if (material.kind === 'list') {
        return (
            <div className="flex flex-col gap-2">
                <h3 className="m3-title-small">{material.title}</h3>
                <ol className="m3-body-medium flex list-decimal flex-col gap-1.5 pl-5">
                    {material.items.map((item) => (
                        <li key={item}>{item}</li>
                    ))}
                </ol>
            </div>
        )
    }
    const alignEnd = (index: number) =>
        material.amountColumns?.includes(index) ? 'text-right' : 'text-left'
    return (
        <div className="flex flex-col gap-2">
            <h3 className="m3-title-small">{material.title}</h3>
            {material.notes?.map((note) => (
                <p key={note} className="m3-body-small text-on-surface-variant">
                    {note}
                </p>
            ))}
            <div className="overflow-x-auto">
                <table className="m3-body-small w-full border-collapse">
                    <thead>
                        <tr className="border-b border-outline-variant">
                            {material.columns.map((column, index) => (
                                <th
                                    key={column}
                                    className={cn(
                                        'px-1.5 py-1.5 font-medium whitespace-nowrap text-on-surface-variant',
                                        alignEnd(index),
                                    )}
                                >
                                    {column}
                                </th>
                            ))}
                        </tr>
                    </thead>
                    <tbody>
                        {material.rows.map((row) => (
                            <tr
                                key={row.join('|')}
                                className="border-b border-outline-variant/60"
                            >
                                {row.map((cell, index) => (
                                    <td
                                        key={`${material.columns[index]}-${cell}`}
                                        className={cn(
                                            'px-1.5 py-1.5 tabular-nums',
                                            material.amountColumns?.includes(
                                                index,
                                            ) || index === 0
                                                ? 'whitespace-nowrap'
                                                : undefined,
                                            alignEnd(index),
                                        )}
                                    >
                                        {cell}
                                    </td>
                                ))}
                            </tr>
                        ))}
                        {material.total ? (
                            <tr>
                                {material.total.map((cell, index) => (
                                    <td
                                        key={`${material.columns[index]}-${cell}`}
                                        className={cn(
                                            'px-1.5 py-1.5 font-medium tabular-nums',
                                            alignEnd(index),
                                        )}
                                    >
                                        {cell}
                                    </td>
                                ))}
                            </tr>
                        ) : null}
                    </tbody>
                </table>
            </div>
            {material.footer ? (
                <p className="m3-body-small font-medium">{material.footer}</p>
            ) : null}
        </div>
    )
}

export function MaterialBlock({
    title,
    materials,
}: {
    title: string
    materials: readonly UsabilityMaterial[]
}) {
    const t = useT()
    const [open, setOpen] = useState(false)
    return (
        <Surface>
            <button
                type="button"
                onClick={() => setOpen((value) => !value)}
                aria-expanded={open}
                className="flex cursor-pointer items-center gap-3 text-left"
            >
                <Icon name="description" className="text-on-surface-variant" />
                <span className="m3-title-small flex-1">{title}</span>
                <span className="m3-label-large text-on-surface-variant">
                    {open ? t.usability.hideMaterial : t.usability.showMaterial}
                </span>
            </button>
            {open ? (
                <div className="flex flex-col gap-5 border-t border-outline-variant pt-3">
                    {materials.map((material) => (
                        <MaterialView
                            key={material.title}
                            material={material}
                        />
                    ))}
                </div>
            ) : null}
        </Surface>
    )
}
