import { useNavigate } from 'react-router-dom'
import { AuthFrame } from '@/components/auth/auth-scaffold'
import { ForgotPasswordPanel } from '@/pages/auth/forgot-password-panel'

/**
 * The reset-password request as its own route. The login screen shows the
 * same panel inline (as native does); this route exists because the address is
 * linkable and gets shared.
 */
export function ForgotPassword() {
    const navigate = useNavigate()
    return (
        <AuthFrame>
            <ForgotPasswordPanel onBack={() => navigate('/login')} />
        </AuthFrame>
    )
}
