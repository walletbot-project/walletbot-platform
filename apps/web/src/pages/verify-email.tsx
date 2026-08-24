import { useNavigate, useSearchParams } from 'react-router-dom'
import { AuthFrame, AuthMessagePanel } from '@/components/auth/auth-scaffold'
import { type Messages, useT } from '@/lib/i18n'

type VerifyState = {
    icon: string
    title: string
    description: string
}

const stateForError = (error: string | null, t: Messages): VerifyState => {
    if (error === null) {
        return {
            icon: 'mark_email_read',
            title: t.auth.emailVerifiedTitle,
            description: t.auth.emailVerifiedDescription,
        }
    }
    if (error === 'TOKEN_EXPIRED') {
        return {
            icon: 'schedule',
            title: t.auth.linkExpiredTitle,
            description: t.auth.linkExpiredDescription,
        }
    }
    // INVALID_TOKEN, USER_NOT_FOUND, INVALID_USER, or anything unexpected.
    return {
        icon: 'link_off',
        title: t.auth.verifyFailedTitle,
        description: t.auth.verifyFailedDescription,
    }
}

export function VerifyEmail() {
    const t = useT()
    const navigate = useNavigate()
    const [searchParams] = useSearchParams()
    const state = stateForError(searchParams.get('error'), t)

    return (
        <AuthFrame>
            <AuthMessagePanel
                icon={state.icon}
                title={state.title}
                subtitle={state.description}
                actionLabel={t.auth.signIn}
                onAction={() => navigate('/login')}
            />
        </AuthFrame>
    )
}
