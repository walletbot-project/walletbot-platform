import { useEffect, useState } from 'react'
import { IconColorPicker } from '@/components/icon-color-picker'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
    Dialog,
    DialogContent,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { CATEGORY_DEFAULT_ICON, CATEGORY_ICONS } from '@/lib/category-icons'
import { CATEGORY_DEFAULT_COLOR, COLOR_OPTIONS } from '@/lib/entity-colors'

export type CategoryFormValue = {
    name: string
    description: string
    color: string
    icon: string
}

const NAME_SUGGESTIONS: { label: string; icon: string }[] = [
    { label: 'Supermercado', icon: 'shopping_cart' },
    { label: 'Transporte', icon: 'transport' },
    { label: 'Servicios', icon: 'receipt' },
]

export function CategoryDialog({
    open,
    onOpenChange,
    onSubmit,
}: {
    open: boolean
    onOpenChange: (open: boolean) => void
    onSubmit: (value: CategoryFormValue) => Promise<void>
}) {
    const [name, setName] = useState('')
    const [description, setDescription] = useState('')
    const [color, setColor] = useState(CATEGORY_DEFAULT_COLOR)
    const [icon, setIcon] = useState(CATEGORY_DEFAULT_ICON)
    const [submitting, setSubmitting] = useState(false)

    useEffect(() => {
        if (open) {
            setName('')
            setDescription('')
            setColor(CATEGORY_DEFAULT_COLOR)
            setIcon(CATEGORY_DEFAULT_ICON)
        }
    }, [open])

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault()
        const trimmed = name.trim()
        if (!trimmed) return
        setSubmitting(true)
        try {
            await onSubmit({
                name: trimmed,
                description: description.trim(),
                color,
                icon,
            })
        } finally {
            setSubmitting(false)
        }
    }

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent>
                <DialogHeader>
                    <DialogTitle>Nueva categoría</DialogTitle>
                </DialogHeader>
                <form onSubmit={handleSubmit} className="flex flex-col gap-4">
                    <div className="flex flex-wrap gap-2">
                        {NAME_SUGGESTIONS.map((s) => (
                            <Badge
                                key={s.label}
                                render={
                                    <button
                                        type="button"
                                        onClick={() => {
                                            setName(s.label)
                                            setIcon(s.icon)
                                        }}
                                    />
                                }
                                variant="outline"
                                className="cursor-pointer"
                            >
                                {s.label}
                            </Badge>
                        ))}
                    </div>

                    <div className="flex flex-col gap-2">
                        <Label htmlFor="category-name">Nombre</Label>
                        <Input
                            id="category-name"
                            value={name}
                            onChange={(e) => setName(e.target.value)}
                            placeholder="Ej: Supermercado, Transporte…"
                            autoFocus
                            required
                        />
                    </div>

                    <div className="flex flex-col gap-2">
                        <Label htmlFor="category-description">
                            Descripción (opcional)
                        </Label>
                        <Textarea
                            id="category-description"
                            value={description}
                            onChange={(e) => setDescription(e.target.value)}
                            rows={2}
                        />
                    </div>

                    <div className="flex flex-col gap-2">
                        <Label>Ícono y color</Label>
                        <IconColorPicker
                            icon={icon}
                            color={color}
                            onIconChange={setIcon}
                            onColorChange={setColor}
                            icons={CATEGORY_ICONS}
                            colors={COLOR_OPTIONS}
                        />
                    </div>

                    <DialogFooter>
                        <Button
                            type="button"
                            variant="outline"
                            onClick={() => onOpenChange(false)}
                            disabled={submitting}
                        >
                            Cancelar
                        </Button>
                        <Button
                            type="submit"
                            disabled={submitting || !name.trim()}
                        >
                            Crear
                        </Button>
                    </DialogFooter>
                </form>
            </DialogContent>
        </Dialog>
    )
}
