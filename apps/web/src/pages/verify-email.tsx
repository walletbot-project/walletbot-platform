import { useNavigate, useSearchParams } from 'react-router-dom'
import {
    AuthHeroHeader,
    AuthPanel,
    AuthPanelTitle,
    AuthPrimaryButton,
    AuthScaffold,
} from '@/components/auth/auth-scaffold'
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
        <AuthScaffold>
            <AuthHeroHeader subtitle={t.auth.signInToContinue} />
            <div className="mt-5.5">
                <AuthPanel>
                    <AuthPanelTitle
                        icon={state.icon}
                        title={state.title}
                        subtitle={state.description}
                    />
                    <div className="mt-4">
                        <AuthPrimaryButton
                            submitting={false}
                            label={t.auth.signIn}
                            onPress={() => navigate('/login')}
                        />
                    </div>
                </AuthPanel>
            </div>
        </AuthScaffold>
    )
}
