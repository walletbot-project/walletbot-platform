import { t } from '@wallet-bot/shared'
import { LogOut } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useAuth } from '@/hooks/use-auth'

export function DangerZone() {
    const { signOut } = useAuth()

    return (
        <div className="rounded-xl border border-destructive/30 p-6">
            <div className="flex items-center justify-between">
                <div>
                    <h3 className="text-sm font-medium">
                        {t('common.signOut')}
                    </h3>
                    <p className="text-xs text-muted-foreground">
                        Sign out of your account on this device.
                    </p>
                </div>
                <Button
                    variant="destructive"
                    size="sm"
                    onClick={() => signOut()}
                >
                    <LogOut className="size-4" />
                    {t('common.signOut')}
                </Button>
            </div>
        </div>
    )
}
