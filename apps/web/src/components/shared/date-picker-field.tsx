import { format, parseISO } from 'date-fns'
import { CalendarIcon } from 'lucide-react'
import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Calendar } from '@/components/ui/calendar'
import {
    Popover,
    PopoverContent,
    PopoverTrigger,
} from '@/components/ui/popover'
import { cn } from '@/lib/utils'

interface DatePickerFieldProps {
    value: string | undefined
    onChange: (date: string) => void
    placeholder?: string
    className?: string
}

export function DatePickerField({
    value,
    onChange,
    placeholder = 'Pick a date',
    className,
}: DatePickerFieldProps) {
    const [open, setOpen] = useState(false)
    const selected = value ? parseISO(value) : undefined

    return (
        <Popover open={open} onOpenChange={setOpen}>
            <PopoverTrigger
                render={
                    <Button
                        variant="outline"
                        className={cn(
                            'h-8 justify-start gap-2 font-normal',
                            !value && 'text-muted-foreground',
                            className,
                        )}
                    >
                        <CalendarIcon className="size-3.5" />
                        {value
                            ? format(parseISO(value), 'MMM d, yyyy')
                            : placeholder}
                    </Button>
                }
            />
            <PopoverContent className="w-auto p-0" align="start">
                <Calendar
                    mode="single"
                    selected={selected}
                    onSelect={(date) => {
                        if (date) {
                            onChange(format(date, 'yyyy-MM-dd'))
                            setOpen(false)
                        }
                    }}
                    defaultMonth={selected}
                />
            </PopoverContent>
        </Popover>
    )
}
