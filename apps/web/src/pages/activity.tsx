import { List } from 'lucide-react'
import { Placeholder } from '@/components/layout/placeholder'

export function Activity() {
    return (
        <Placeholder
            icon={List}
            title="Activity"
            description="Recent transactions will show up here."
        />
    )
}
