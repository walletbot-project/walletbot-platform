// @vitest-environment jsdom

import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import { afterEach, beforeEach, expect, it, vi } from 'vitest'

const f = vi.hoisted(() => ({
    state: {
        isConnected: false,
        isConnecting: false,
        isMicCaptureActive: false,
        isMicOn: false,
        micLevel: 0,
    },
    voice: {
        devices: [],
        selectedDeviceId: undefined,
        messages: [],
        attach: vi.fn(),
        detach: vi.fn(),
        connect: vi.fn(async () => {}),
        disconnect: vi.fn(),
        openMic: vi.fn(async () => {}),
        setMicOn: vi.fn(),
        sendText: vi.fn(),
        setComposing: vi.fn(),
        markReported: vi.fn(),
        getSessionInfo: vi.fn(() => ({})),
        handleDeviceChange: vi.fn(),
    },
}))

vi.mock('convex/react', () => ({
    useQuery: () => ({}),
    useConvex: () => ({ query: vi.fn() }),
}))
vi.mock('react-router-dom', () => ({ useNavigate: () => vi.fn() }))
vi.mock('@/hooks/use-voice-session', () => ({
    // A fresh object per render, as the real provider gives one per update.
    useVoiceSession: () => ({ ...f.state, ...f.voice }),
}))
vi.mock('@/lib/i18n', async (importOriginal) => {
    const original = await importOriginal<typeof import('@/lib/i18n')>()
    return {
        ...original,
        useT: () => original.en,
        useFormatLocale: () => 'en',
    }
})
vi.mock('@/pages/add/report-response-sheet', () => ({
    ReportResponseSheet: () => null,
}))
vi.mock('@/pages/add-action-widget', () => ({ ActionWidget: () => null }))

const { Add } = await import('./add')

let container: HTMLDivElement
let root: Root

function render() {
    act(() => root.render(<Add />))
}

function setVoice(next: Partial<typeof f.state>) {
    Object.assign(f.state, next)
    render()
}

function byText(text: string): HTMLElement | undefined {
    return [...container.querySelectorAll<HTMLElement>('button, p, span')].find(
        (el) => el.textContent?.trim() === text,
    )
}

/** Icons are ligatures, so a button's text also carries its icon name. */
function button(label: string): HTMLButtonElement | undefined {
    return [...container.querySelectorAll('button')].find((el) =>
        el.textContent?.endsWith(label),
    )
}

function byLabel(label: string): HTMLButtonElement {
    const el = container.querySelector<HTMLButtonElement>(
        `button[aria-label="${label}"]`,
    )
    if (!el) throw new Error(`no button labelled ${label}`)
    return el
}

/** Lets the mocked `openMic` promise settle, as the browser would. */
async function flush() {
    await act(async () => {})
}

function pointer(el: Element, type: string, clientY = 0) {
    act(() => {
        el.dispatchEvent(
            new PointerEvent(type, {
                bubbles: true,
                pointerId: 1,
                button: 0,
                clientY,
            }),
        )
    })
}

beforeEach(() => {
    vi.useFakeTimers()
    Object.assign(f.state, {
        isConnected: false,
        isConnecting: false,
        isMicCaptureActive: false,
        isMicOn: false,
        micLevel: 0,
    })
    for (const fn of Object.values(f.voice)) {
        if (typeof fn === 'function' && 'mockClear' in fn) fn.mockClear()
    }
    HTMLElement.prototype.setPointerCapture = vi.fn()
    container = document.createElement('div')
    document.body.append(container)
    root = createRoot(container)
    render()
})

afterEach(() => {
    act(() => root.unmount())
    container.remove()
    vi.useRealTimers()
})

it('welcomes with a start button and no status pill', () => {
    expect(container.querySelector('h2')?.textContent).toBe('How can I help?')
    expect(
        byText('Tell me about an expense or ask about your accounts'),
    ).toBeDefined()
    expect(button('Start talking')).toBeDefined()
    expect(byText('Hold to talk')).toBeDefined()
    expect(byText('connecting')).toBeUndefined()
    expect(byText('idle')).toBeUndefined()
})

it('a tap starts a hands-free session', () => {
    const mic = byLabel('Start talking')
    pointer(mic, 'pointerdown')
    act(() => vi.advanceTimersByTime(100))
    pointer(mic, 'pointerup')
    // Nothing happens before the click, so the click can't land on the bar
    // that the tap swaps in.
    expect(f.voice.connect).not.toHaveBeenCalled()
    act(() => mic.click())
    expect(f.voice.connect).toHaveBeenCalledWith('audio')

    setVoice({ isConnecting: true })
    expect(byLabel('Switch to text')).toBeDefined()
    expect(button('Pause')?.disabled).toBe(true)
})

it('holding talks and releasing mutes through the long-press path', () => {
    setVoice({ isConnected: true })
    const mic = byLabel('Start talking')
    pointer(mic, 'pointerdown', 500)
    act(() => vi.advanceTimersByTime(300))
    expect(f.voice.openMic).toHaveBeenCalledWith({ turnOn: true })
    setVoice({ isMicCaptureActive: true, isMicOn: true })
    expect(byText('Slide up to lock')).toBeDefined()

    pointer(mic, 'pointerup', 500)
    expect(f.voice.setMicOn).toHaveBeenCalledWith(false)
    expect(byText('Slide up to lock')).toBeUndefined()

    // The click that follows a hold is not a tap.
    setVoice({ isMicCaptureActive: false, isMicOn: false })
    f.voice.openMic.mockClear()
    act(() => mic.click())
    expect(f.voice.openMic).not.toHaveBeenCalled()
})

it('sliding up locks, then pause, resume and switch to text reuse the tap path', async () => {
    setVoice({ isConnected: true })
    const mic = byLabel('Start talking')
    pointer(mic, 'pointerdown', 500)
    act(() => vi.advanceTimersByTime(300))
    await flush()
    setVoice({ isMicCaptureActive: true, isMicOn: true })
    pointer(mic, 'pointermove', 400)
    expect(byText('Slide up to lock')).toBeUndefined()
    pointer(mic, 'pointerup', 400)
    expect(f.voice.setMicOn).not.toHaveBeenCalled()

    button('Pause')?.click()
    render()
    expect(f.voice.setMicOn).toHaveBeenCalledWith(false)
    setVoice({ isMicCaptureActive: false, isMicOn: false })
    expect(byText('Mic paused')).toBeDefined()

    f.voice.openMic.mockClear()
    button('Resume')?.click()
    render()
    expect(f.voice.openMic).toHaveBeenCalledWith({ turnOn: true })
    await flush()
    setVoice({ isMicCaptureActive: true, isMicOn: true })

    f.voice.setMicOn.mockClear()
    byLabel('Switch to text').click()
    render()
    expect(f.voice.setMicOn).toHaveBeenCalledWith(false)
    setVoice({ isMicCaptureActive: false, isMicOn: false })
    expect(container.querySelector('textarea')).not.toBeNull()
})
