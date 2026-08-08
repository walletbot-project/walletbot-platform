import { Home as HomeIcon } from 'lucide-react'
import { Placeholder } from '@/components/layout/placeholder'
import { useT } from '@/lib/i18n'

export default function Home() {
    const t = useT()
    return <Placeholder icon={HomeIcon} title={t.nav.home} />
}
