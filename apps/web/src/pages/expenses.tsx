import { api } from '@wallet-bot/backend/api'
import { useMutation, useQuery } from 'convex/react'
import { format } from 'date-fns'
import { ExternalLink, Plus, Trash2 } from 'lucide-react'
import { useState } from 'react'
import { Link } from 'react-router-dom'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
    Card,
    CardContent,
    CardDescription,
    CardHeader,
    CardTitle,
} from '@/components/ui/card'
import {
    Dialog,
    DialogClose,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
    DialogTrigger,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'

const MOCK_USER_ID = 'mock-user-demo'

const CATEGORIES = [
    'groceries',
    'transport',
    'dining',
    'entertainment',
    'utilities',
    'health',
    'shopping',
    'other',
] as const

const CATEGORY_COLORS: Record<string, string> = {
    groceries:
        'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200',
    transport: 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200',
    dining: 'bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200',
    entertainment:
        'bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200',
    utilities: 'bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200',
    health: 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200',
    shopping: 'bg-pink-100 text-pink-800 dark:bg-pink-900 dark:text-pink-200',
    other: 'bg-muted text-muted-foreground',
}

export function Expenses() {
    const expenses = useQuery(api.expenses.queries.listExpensesByDateRange, {
        userId: MOCK_USER_ID,
        startDate: '2000-01-01',
        endDate: '2099-12-31',
    })
    const addExpense = useMutation(api.expenses.mutations.addExpense)
    const deleteExpense = useMutation(api.expenses.mutations.deleteExpense)

    const [dialogOpen, setDialogOpen] = useState(false)
    const [amount, setAmount] = useState('')
    const [description, setDescription] = useState('')
    const [category, setCategory] = useState<string>('other')
    const [date, setDate] = useState(() => format(new Date(), 'yyyy-MM-dd'))
    const [submitting, setSubmitting] = useState(false)

    const handleAdd = async () => {
        const parsed = Number.parseFloat(amount)
        if (!parsed || parsed <= 0 || !description.trim()) return

        setSubmitting(true)
        await addExpense({
            userId: MOCK_USER_ID,
            amount: Math.round(parsed * 100),
            description: description.trim(),
            category,
            date,
        })

        setAmount('')
        setDescription('')
        setCategory('other')
        setDate(format(new Date(), 'yyyy-MM-dd'))
        setDialogOpen(false)
        setSubmitting(false)
    }

    const handleDelete = async (expenseId: string) => {
        await deleteExpense({
            userId: MOCK_USER_ID,
            expenseId,
        })
    }

    const loading = expenses === undefined
    const totalCents = expenses?.reduce((sum, e) => sum + e.amount, 0) ?? 0

    return (
        <div className="flex min-h-screen items-center justify-center bg-background p-4">
            <Card className="w-full max-w-lg">
                <CardHeader>
                    <div className="flex items-center justify-between">
                        <div>
                            <CardTitle>Expenses</CardTitle>
                            <CardDescription>
                                Total: ${(totalCents / 100).toFixed(2)} across{' '}
                                {expenses?.length ?? 0} expenses
                            </CardDescription>
                        </div>
                        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
                            <DialogTrigger>
                                <Button size="sm">
                                    <Plus />
                                    Add
                                </Button>
                            </DialogTrigger>
                            <DialogContent>
                                <DialogHeader>
                                    <DialogTitle>Add Expense</DialogTitle>
                                    <DialogDescription>
                                        Add a new expense to your tracker.
                                    </DialogDescription>
                                </DialogHeader>
                                <div className="flex flex-col gap-3">
                                    <div className="flex flex-col gap-1">
                                        <label
                                            htmlFor="expense-amount"
                                            className="text-sm font-medium"
                                        >
                                            Amount ($)
                                        </label>
                                        <Input
                                            id="expense-amount"
                                            type="number"
                                            step="0.01"
                                            min="0.01"
                                            placeholder="0.00"
                                            value={amount}
                                            onChange={(e) =>
                                                setAmount(e.target.value)
                                            }
                                        />
                                    </div>
                                    <div className="flex flex-col gap-1">
                                        <label
                                            htmlFor="expense-description"
                                            className="text-sm font-medium"
                                        >
                                            Description
                                        </label>
                                        <Input
                                            id="expense-description"
                                            placeholder="What was it for?"
                                            value={description}
                                            onChange={(e) =>
                                                setDescription(e.target.value)
                                            }
                                        />
                                    </div>
                                    <div className="flex flex-col gap-1">
                                        <span className="text-sm font-medium">
                                            Category
                                        </span>
                                        <div className="flex flex-wrap gap-1">
                                            {CATEGORIES.map((c) => (
                                                <button
                                                    key={c}
                                                    type="button"
                                                    onClick={() =>
                                                        setCategory(c)
                                                    }
                                                    className={`rounded-md px-2 py-1 text-xs capitalize transition-colors ${
                                                        category === c
                                                            ? 'ring-2 ring-ring ring-offset-1'
                                                            : ''
                                                    } ${CATEGORY_COLORS[c]}`}
                                                >
                                                    {c}
                                                </button>
                                            ))}
                                        </div>
                                    </div>
                                    <div className="flex flex-col gap-1">
                                        <label
                                            htmlFor="expense-date"
                                            className="text-sm font-medium"
                                        >
                                            Date
                                        </label>
                                        <Input
                                            id="expense-date"
                                            type="date"
                                            value={date}
                                            onChange={(e) =>
                                                setDate(e.target.value)
                                            }
                                        />
                                    </div>
                                </div>
                                <DialogFooter>
                                    <DialogClose>
                                        <Button variant="outline">
                                            Cancel
                                        </Button>
                                    </DialogClose>
                                    <Button
                                        onClick={handleAdd}
                                        disabled={
                                            submitting ||
                                            !amount ||
                                            !description.trim()
                                        }
                                    >
                                        {submitting
                                            ? 'Adding...'
                                            : 'Add Expense'}
                                    </Button>
                                </DialogFooter>
                            </DialogContent>
                        </Dialog>
                    </div>
                </CardHeader>
                <CardContent>
                    {loading ? (
                        <p className="py-8 text-center text-sm text-muted-foreground">
                            Loading...
                        </p>
                    ) : expenses.length === 0 ? (
                        <p className="py-8 text-center text-sm text-muted-foreground">
                            No expenses yet. Add one or use the voice assistant.
                        </p>
                    ) : (
                        <div className="flex flex-col gap-2">
                            {expenses.map((expense) => (
                                <div
                                    key={expense._id}
                                    className="flex items-center gap-3 rounded-lg border p-3"
                                >
                                    <div className="flex-1">
                                        <div className="flex items-center gap-2">
                                            <span className="text-sm font-medium">
                                                {expense.description}
                                            </span>
                                            <Badge
                                                className={`text-xs capitalize ${CATEGORY_COLORS[expense.category] ?? CATEGORY_COLORS.other}`}
                                            >
                                                {expense.category}
                                            </Badge>
                                        </div>
                                        <span className="text-xs text-muted-foreground">
                                            {expense.date}
                                        </span>
                                    </div>
                                    <span className="text-sm font-semibold tabular-nums">
                                        {expense.currency === 'ARS'
                                            ? 'ARS'
                                            : 'USD'}{' '}
                                        ${(expense.amount / 100).toFixed(2)}
                                    </span>
                                    <Button
                                        variant="ghost"
                                        size="icon-xs"
                                        onClick={() =>
                                            handleDelete(expense._id)
                                        }
                                    >
                                        <Trash2 />
                                    </Button>
                                </div>
                            ))}
                        </div>
                    )}

                    {/* Nav link */}
                    <div className="mt-4">
                        <Link
                            to="/live-demo-cloud"
                            className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
                        >
                            <ExternalLink className="size-3.5" />
                            Voice assistant
                        </Link>
                    </div>
                </CardContent>
            </Card>
        </div>
    )
}
