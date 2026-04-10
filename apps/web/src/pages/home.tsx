import { LogOut } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useAuth, useUser } from '@/hooks/use-auth'

export function Home() {
    const user = useUser()
    const { signOut } = useAuth()

    return (
        <div className="flex min-h-screen items-center justify-center bg-background">
            <div className="flex flex-col items-center gap-4">
                <h1 className="text-2xl font-semibold tracking-tight">
                    Wallet Bot
                </h1>
                <p className="text-sm text-muted-foreground">
                    Welcome, {user.name}
                </p>
                <Button variant="outline" onClick={() => signOut()}>
                    <LogOut />
                    Sign out
                </Button>
            </div>
        </div>
    )
}
