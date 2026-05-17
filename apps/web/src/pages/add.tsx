import { Plus } from 'lucide-react'
import { Placeholder } from '@/components/layout/placeholder'

export function Add() {
    return (
        <Placeholder
            icon={Plus}
            title="Add"
            description="Create a new transaction."
        />
    )
}
