// @vitest-environment jsdom

import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import type { ChatMessage } from '@/hooks/use-voice'

const f = vi.hoisted(() => ({
    flags: {} as { debugToolCalls?: boolean; agentRecordHint?: boolean },
    state: {
        isConnected: false,
        isConnecting: false,
        isMicCaptureActive: false,
        isMicOpening: false,
        isMicOn: false,
        isNoteFull: false,
        micLevel: 0,
        mode: 'chat' as 'chat' | 'live',
    },
    voice: {
        devices: [],
        selectedDeviceId: undefined,
        messages: [] as ChatMessage[],
        attach: vi.fn(),
        detach: vi.fn(),
        connect: vi.fn(async () => {}),
        disconnect: vi.fn(),
        openMic: vi.fn(async () => {}),
        setMicOn: vi.fn(),
        pauseMic: vi.fn(),
        cancelVoiceNote: vi.fn(),
        enterLive: vi.fn(async () => {}),
        exitLive: vi.fn(),
        sendText: vi.fn(),
        setComposing: vi.fn(),
        markReported: vi.fn(),
        getSessionInfo: vi.fn(() => ({})),
        handleDeviceChange: vi.fn(),
    },
}))

vi.mock('convex/react', () => ({
    useQuery: () => f.flags,
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
        isMicOpening: false,
        isMicOn: false,
        isNoteFull: false,
        micLevel: 0,
        mode: 'chat',
    })
    f.flags = {}
    f.voice.messages = []
    for (const fn of Object.values(f.voice)) {
        if (typeof fn === 'function' && 'mockClear' in fn) fn.mockClear()
    }
    HTMLElement.prototype.setPointerCapture = vi.fn()
    HTMLElement.prototype.scrollIntoView = vi.fn()
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
    expect(button('Start call')).toBeDefined()
    expect(byText('Hands-free mode')).toBeDefined()
    expect(byText('Tap or hold to record a voice note')).toBeDefined()
    expect(byText('connecting')).toBeUndefined()
    expect(byText('idle')).toBeUndefined()
})

it('a tap starts a locked voice note', () => {
    const mic = byLabel('Record a voice note')
    pointer(mic, 'pointerdown')
    act(() => vi.advanceTimersByTime(100))
    pointer(mic, 'pointerup')
    // Nothing happens before the click, so the click can't land on the bar
    // that the tap swaps in.
    expect(f.voice.connect).not.toHaveBeenCalled()
    act(() => mic.click())
    expect(f.voice.connect).toHaveBeenCalledWith('audio')

    setVoice({ isConnecting: true })
    expect(byLabel('Send')).toBeDefined()
    expect(button('Pause')?.disabled).toBe(true)
    expect(byText('On a call')).toBeUndefined()
})

it('holding records and releasing sends through the long-press path', () => {
    setVoice({ isConnected: true })
    const mic = byLabel('Record a voice note')
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

it('sliding up locks; pause keeps the note open and Send ends it', async () => {
    setVoice({ isConnected: true })
    const mic = byLabel('Record a voice note')
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
    expect(f.voice.pauseMic).toHaveBeenCalledOnce()
    expect(f.voice.setMicOn).not.toHaveBeenCalled()
    setVoice({ isMicCaptureActive: false, isMicOn: false })
    expect(byText('Mic paused')).toBeDefined()

    f.voice.openMic.mockClear()
    button('Resume')?.click()
    render()
    expect(f.voice.openMic).toHaveBeenCalledWith({ turnOn: true })
    await flush()
    setVoice({ isMicCaptureActive: true, isMicOn: true })

    f.voice.setMicOn.mockClear()
    byLabel('Send').click()
    render()
    expect(f.voice.setMicOn).toHaveBeenCalledWith(false)
    setVoice({ isMicCaptureActive: false, isMicOn: false })
    expect(container.querySelector('textarea')).not.toBeNull()
})

it('keeps the composer focused with the mic open and switches to text on typing', () => {
    const textarea = container.querySelector('textarea')
    if (!textarea) throw new Error('no composer')
    act(() => textarea.focus())

    const mic = byLabel('Record a voice note')
    pointer(mic, 'pointerdown')
    pointer(mic, 'pointerup')
    act(() => mic.click())
    expect(f.voice.connect).toHaveBeenCalledWith('audio')
    setVoice({ isConnecting: true })
    expect(byLabel('Send')).toBeDefined()
    expect(container.querySelector('textarea')).toBe(textarea)
    expect(document.activeElement).toBe(textarea)

    const setValue = Object.getOwnPropertyDescriptor(
        HTMLTextAreaElement.prototype,
        'value',
    )?.set
    act(() => {
        setValue?.call(textarea, 'café')
        textarea.dispatchEvent(new Event('input', { bubbles: true }))
    })
    expect(f.voice.setMicOn).toHaveBeenCalledWith(false)
    setVoice({ isConnecting: false })
    expect(container.querySelector('.sr-only')).toBeNull()
    expect(textarea.value).toBe('café')
})

it('typing while the mic is still opening stops it and brings the composer back', async () => {
    setVoice({ isConnected: true })
    let opened = () => {}
    f.voice.openMic.mockImplementationOnce(
        () =>
            new Promise<void>((resolve) => {
                opened = resolve
            }),
    )
    const textarea = container.querySelector('textarea')
    if (!textarea) throw new Error('no composer')

    act(() => byLabel('Record a voice note').click())
    expect(f.voice.openMic).toHaveBeenCalledWith({ turnOn: true })
    expect(byLabel('Send')).toBeDefined()

    const setValue = Object.getOwnPropertyDescriptor(
        HTMLTextAreaElement.prototype,
        'value',
    )?.set
    act(() => {
        setValue?.call(textarea, 'café')
        textarea.dispatchEvent(new Event('input', { bubbles: true }))
    })
    expect(f.voice.setMicOn).toHaveBeenCalledWith(false)
    await act(async () => opened())
    expect(container.querySelector('.sr-only')).toBeNull()
    expect(textarea.value).toBe('café')
})

it('Discard drops a locked note and brings the composer back', async () => {
    setVoice({ isConnected: true })
    act(() => byLabel('Record a voice note').click())
    await flush()
    setVoice({ isMicCaptureActive: true, isMicOn: true })
    expect(byLabel('Send')).toBeDefined()

    act(() => byLabel('Discard voice note').click())
    expect(f.voice.cancelVoiceNote).toHaveBeenCalledOnce()
    expect(f.voice.setMicOn).not.toHaveBeenCalledWith(false)
    setVoice({ isMicCaptureActive: false, isMicOn: false })
    expect(container.querySelector('.sr-only')).toBeNull()
})

it('a held note that fills up waits for Send, then the composer comes back', async () => {
    setVoice({ isConnected: true })
    const mic = byLabel('Record a voice note')
    pointer(mic, 'pointerdown', 500)
    act(() => vi.advanceTimersByTime(300))
    await flush()
    setVoice({ isMicCaptureActive: true, isMicOn: true })
    expect(byText('Slide up to lock')).toBeDefined()

    setVoice({ isMicCaptureActive: false, isMicOn: false, isNoteFull: true })
    expect(byText('5 minute limit')).toBeDefined()
    expect(byText('Slide up to lock')).toBeUndefined()
    expect(button('Resume')?.disabled).toBe(true)
    expect(f.voice.setMicOn).not.toHaveBeenCalledWith(false)

    act(() => byLabel('Send').click())
    expect(f.voice.setMicOn).toHaveBeenCalledWith(false)
    setVoice({ isNoteFull: false })
    expect(byText('Slide up to lock')).toBeUndefined()
    expect(container.querySelector('.sr-only')).toBeNull()
})

it('the welcome button and the composer button both enter live mode', () => {
    act(() => button('Start call')?.click())
    expect(f.voice.enterLive).toHaveBeenCalledOnce()
    act(() => byLabel('Start call').click())
    expect(f.voice.enterLive).toHaveBeenCalledTimes(2)
    expect(f.voice.connect).not.toHaveBeenCalled()

    // No second session while one is still connecting.
    setVoice({ isConnecting: true })
    expect(byLabel('Start call').disabled).toBe(true)
})

it('live mode mutes with Pause and leaves with X, keeping the chat', () => {
    f.voice.messages = [
        { kind: 'user', id: 'u1', at: new Date(), text: 'hola', isFinal: true },
    ]
    setVoice({
        mode: 'live',
        isConnected: true,
        isMicCaptureActive: true,
        isMicOn: true,
    })
    expect(container.querySelector('button[aria-label="Start call"]')).toBeNull()
    expect(byText('On a call')).toBeDefined()
    expect(
        container.querySelector('button[aria-label="Discard voice note"]'),
    ).toBeNull()
    expect(
        container.querySelector('button[aria-label="Record a voice note"]'),
    ).toBeNull()

    button('Pause')?.click()
    expect(f.voice.setMicOn).toHaveBeenCalledWith(false)
    expect(f.voice.pauseMic).not.toHaveBeenCalled()

    // Coming back to a live conversation whose mic was released.
    setVoice({ isMicCaptureActive: false, isMicOn: false })
    expect(button('Resume')?.disabled).toBe(false)
    act(() => button('Resume')?.click())
    expect(f.voice.openMic).toHaveBeenCalledWith({ turnOn: true })

    act(() => byLabel('End call').click())
    expect(f.voice.exitLive).toHaveBeenCalledOnce()
    expect(f.voice.disconnect).not.toHaveBeenCalled()
    expect(byText('hola')).toBeDefined()
})

it('typing in live mode leaves it', () => {
    setVoice({
        mode: 'live',
        isConnected: true,
        isMicCaptureActive: true,
        isMicOn: true,
    })
    const textarea = container.querySelector('textarea')
    if (!textarea) throw new Error('no composer')
    const setValue = Object.getOwnPropertyDescriptor(
        HTMLTextAreaElement.prototype,
        'value',
    )?.set
    act(() => {
        setValue?.call(textarea, 'café')
        textarea.dispatchEvent(new Event('input', { bubbles: true }))
    })
    expect(f.voice.exitLive).toHaveBeenCalledOnce()
})

it('agentRecordHint off hides the voice note hint', () => {
    f.flags.agentRecordHint = false
    render()
    expect(byText('Tap or hold to record a voice note')).toBeUndefined()
    expect(button('Start call')).toBeDefined()
})

it('shows tool cards only while debugToolCalls is on', () => {
    f.voice.messages = [
        {
            kind: 'tool',
            id: 't1',
            at: new Date(),
            callId: 'c1',
            name: 'get_balance',
            args: {},
            status: 'completed',
        },
    ]
    render()
    expect(byText('get_balance')).toBeUndefined()

    f.flags.debugToolCalls = true
    render()
    expect(byText('get_balance')).toBeDefined()
})
