import { Fragment, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { cn } from '@/lib/utils'
import { Icon } from './icon'

export type NavigationDestination = {
    /** Material Symbols ligature name for the destination icon. */
    icon: string
    label: string
    /** Route this destination navigates to. */
    to: string
    isActive: boolean
}

/**
 * M3 navigation bar — the compact-window destination switcher, matching the
 * `NavigationBar` in `apps/native/lib/main.dart`: 80dp tall, an active pill
 * indicator behind the icon, and the label always visible.
 */
export function NavigationBar({
    destinations,
}: {
    destinations: readonly NavigationDestination[]
}) {
    return (
        <nav
            aria-label="Primary"
            className="grid shrink-0 grid-flow-col justify-stretch bg-surface-container px-2 pt-3 pb-4"
        >
            {destinations.map((destination) => (
                <NavigationBarItem
                    key={destination.to}
                    destination={destination}
                />
            ))}
        </nav>
    )
}

function NavigationBarItem({
    destination,
}: {
    destination: NavigationDestination
}) {
    const { icon, label, to, isActive } = destination
    return (
        <Link
            to={to}
            aria-current={isActive ? 'page' : undefined}
            className="group flex flex-col items-center gap-1 rounded-2xl pt-0 outline-none"
        >
            <span
                className={cn(
                    'm3-state-layer flex h-8 w-16 items-center justify-center rounded-full transition-colors',
                    isActive
                        ? 'bg-secondary-container text-on-secondary-container'
                        : 'text-on-surface-variant',
                )}
            >
                <Icon name={icon} filled={isActive} />
            </span>
            <span
                className={cn(
                    'm3-label-medium',
                    isActive ? 'text-on-surface' : 'text-on-surface-variant',
                )}
            >
                {label}
            </span>
        </Link>
    )
}

/**
 * The destination the voice FAB is wedged in front of, so it lands between
 * Activity and Accounts — `_AgentCenteredRail._splitIndex` in
 * `apps/native/lib/main.dart`.
 */
const AGENT_SPLIT_INDEX = 2

/**
 * M3 navigation rail — the medium/expanded-window destination switcher,
 * matching the `NavigationRail` in `apps/native/lib/main.dart`: 80dp wide,
 * `labelType: all`, and the voice FAB in the middle of the destination list
 * rather than above it, mirroring the centre-docked FAB of the compact bottom
 * bar.
 */
export function NavigationRail({
    destinations,
    agentButton,
}: {
    destinations: readonly NavigationDestination[]
    agentButton?: ReactNode
}) {
    return (
        <nav
            aria-label="Primary"
            className="flex w-20 shrink-0 flex-col items-center gap-3 overflow-y-auto bg-surface py-2"
        >
            {destinations.map((destination, index) => (
                <Fragment key={destination.to}>
                    {agentButton && index === AGENT_SPLIT_INDEX ? (
                        <div className="pt-2 pb-3">{agentButton}</div>
                    ) : null}
                    <NavigationRailItem destination={destination} />
                </Fragment>
            ))}
        </nav>
    )
}

function NavigationRailItem({
    destination,
}: {
    destination: NavigationDestination
}) {
    const { icon, label, to, isActive } = destination
    return (
        <Link
            to={to}
            aria-current={isActive ? 'page' : undefined}
            className="flex w-full flex-col items-center gap-1 outline-none"
        >
            <span
                className={cn(
                    'm3-state-layer flex h-8 w-14 items-center justify-center rounded-full transition-colors',
                    isActive
                        ? 'bg-secondary-container text-on-secondary-container'
                        : 'text-on-surface-variant',
                )}
            >
                <Icon name={icon} filled={isActive} />
            </span>
            <span
                className={cn(
                    'm3-label-medium text-center',
                    isActive ? 'text-on-surface' : 'text-on-surface-variant',
                )}
            >
                {label}
            </span>
        </Link>
    )
}
