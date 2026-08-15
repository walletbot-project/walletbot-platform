import { useNavigate } from 'react-router-dom'
import { AuthHeroHeader, AuthScaffold } from '@/components/auth/auth-scaffold'
import { useT } from '@/lib/i18n'
import { ForgotPasswordPanel } from '@/pages/auth/forgot-password-panel'

/**
 * The reset-password request as its own route. The login screen shows the
 * same panel inline (as native does); this route exists because the address is
 * linkable and gets shared.
 */
export function ForgotPassword() {
    const t = useT()
    const navigate = useNavigate()
    return (
        <AuthScaffold>
            <AuthHeroHeader subtitle={t.auth.signInToContinue} />
            <div className="mt-5.5">
                <ForgotPasswordPanel onBack={() => navigate('/login')} />
            </div>
        </AuthScaffold>
    )
}
