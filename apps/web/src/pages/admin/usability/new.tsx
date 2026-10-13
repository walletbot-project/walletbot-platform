import { api } from '@wallet-bot/backend/api'
import {
    USABILITY_GROUPS,
    USABILITY_TITLE_MAX_LENGTH,
    type UsabilityGroup,
} from '@wallet-bot/shared'
import { TextField } from 'actify'
import { useMutation } from 'convex/react'
import { type FormEvent, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { FormSubmitButton } from '@/components/entity-form-sections'
import { ChoiceChip } from '@/components/m3/chip'
import { DateField } from '@/components/m3/date-field'
import { FormScreen } from '@/components/m3/form-screen'
import { useToastMutation } from '@/hooks/use-toast-mutation'
import { useT } from '@/lib/i18n'

function todayIso(): string {
    const now = new Date()
    const month = String(now.getMonth() + 1).padStart(2, '0')
    const day = String(now.getDate()).padStart(2, '0')
    return `${now.getFullYear()}-${month}-${day}`
}

export function UsabilitySessionCreate() {
    const t = useT()
    const navigate = useNavigate()
    const create = useMutation(api.v1.usability.mutations.create)
    const { pending, run } = useToastMutation()
    const [group, setGroup] = useState<UsabilityGroup>(1)
    const [sessionDay, setSessionDay] = useState(todayIso)
    const [title, setTitle] = useState('')

    const submit = (event: FormEvent) => {
        event.preventDefault()
        if (!sessionDay) return
        const promise = create({ group, sessionDay, title })
        void run(
            promise,
            {
                loading: t.usability.creating,
                success: t.usability.created,
                error: t.usability.createFailed,
            },
            () => {
                void promise.then((sessionId) =>
                    navigate(`/admin/usability/${sessionId}`, {
                        replace: true,
                    }),
                )
            },
        )
    }

    return (
        <FormScreen
            title={t.usability.newSession}
            onClose={() => navigate('/admin/usability')}
        >
            <form
                onSubmit={submit}
                className="mx-auto flex w-full max-w-2xl flex-col gap-6 p-4"
            >
                <div className="flex flex-col gap-2">
                    <span className="m3-body-medium text-on-surface">
                        {t.usability.group}
                    </span>
                    <div className="flex flex-wrap gap-2">
                        {USABILITY_GROUPS.map((option) => (
                            <ChoiceChip
                                key={option}
                                label={
                                    option === 1
                                        ? t.usability.group1
                                        : t.usability.group2
                                }
                                selected={group === option}
                                onSelect={() => setGroup(option)}
                            />
                        ))}
                    </div>
                </div>

                <div className="flex flex-col gap-1">
                    <DateField
                        label={t.usability.sessionDay}
                        value={sessionDay}
                        onChange={setSessionDay}
                        icon="event"
                    />
                    <p className="m3-body-small px-4 text-on-surface-variant">
                        {t.usability.sessionDayHint}
                    </p>
                </div>

                <TextField
                    variant="outlined"
                    className="w-full"
                    label={t.usability.sessionTitle}
                    value={title}
                    maxLength={USABILITY_TITLE_MAX_LENGTH}
                    onChange={setTitle}
                />

                <p className="m3-body-medium text-on-surface-variant">
                    {t.usability.createDescription}
                </p>

                <FormSubmitButton
                    submitting={pending}
                    isDisabled={pending || !sessionDay}
                    label={t.usability.create}
                />
            </form>
        </FormScreen>
    )
}
