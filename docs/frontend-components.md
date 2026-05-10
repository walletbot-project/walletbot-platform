# Frontend Component Diagram

```mermaid
flowchart TB
    subgraph app["apps/web"]
        main["main.tsx\nApp bootstrap"]
        router["router.tsx\nRoute tree"]
        css["index.css\nGlobal styles"]

        subgraph providers["Providers"]
            convexProvider["ConvexBetterAuthProvider"]
            tooltipProvider["TooltipProvider"]
            toaster["Toaster"]
        end

        subgraph auth["Auth Layer"]
            authClient["lib/auth-client.ts\nBetter Auth client"]
            authContext["lib/auth-context.ts\nAuth context"]
            useAuth["hooks/use-auth.ts"]
            authGuard["components/layout/auth-guard.tsx"]
            publicGuard["components/layout/public-guard.tsx"]
            authProvider["components/layout/auth-provider.tsx"]
        end

        subgraph layouts["Layouts"]
            authLayout["layouts/auth-layout.tsx"]
            rootLayout["layouts/root-layout.tsx"]
            errorBoundary["components/layout/error-boundary.tsx"]
        end

        subgraph pages["Pages"]
            login["pages/login.tsx"]
            home["pages/home.tsx\nLive Voice UI"]
            notFound["pages/not-found.tsx"]
        end

        subgraph voice["Voice Agent"]
            useVoice["hooks/use-voice.ts\nConnection, mic, playback, logs"]
            executors["lib/agent-tools/executors.ts\nTool implementations"]
            helpers["lib/agent-tools/helpers.ts\nTool validation helpers"]
            worklets["public/audio-processors\nCapture/playback worklets"]
        end

        subgraph ui["UI Components"]
            buttons["button, card, badge, tooltip"]
            forms["input, form, checkbox, combobox"]
            overlays["dialog, sheet, popover, dropdown"]
            nav["sidebar, breadcrumb, tabs"]
        end
    end

    subgraph workspace["Workspace Packages"]
        backendApi["@wallet-bot/backend/api\nConvex generated API"]
        sharedTools["@wallet-bot/shared\nTool schemas + definitions"]
    end

    subgraph services["Runtime Services"]
        convex["Convex deployment"]
        authHttp["Better Auth HTTP routes"]
        geminiLive["Gemini Live API"]
        browserAudio["Browser MediaDevices/Web Audio"]
    end

    main --> css
    main --> convexProvider
    main --> tooltipProvider
    main --> toaster
    main --> router

    convexProvider --> authClient
    authClient --> authHttp
    router --> errorBoundary
    router --> publicGuard
    router --> authGuard
    publicGuard --> authLayout
    authGuard --> rootLayout
    authLayout --> login
    rootLayout --> authProvider
    rootLayout --> home
    rootLayout --> notFound

    authProvider --> authClient
    authProvider --> authContext
    useAuth --> authContext
    authGuard --> authClient
    publicGuard --> authClient
    login --> authClient

    home --> useVoice
    home --> buttons
    home --> ui
    useVoice --> backendApi
    backendApi --> convex
    useVoice --> browserAudio
    useVoice --> worklets
    useVoice --> geminiLive
    useVoice --> executors
    executors --> helpers
    executors --> sharedTools
```

## Current Frontend Responsibilities

- `main.tsx` wires Convex, Better Auth, tooltips, routing, and global notifications.
- `router.tsx` separates public login routes from authenticated app routes.
- `home.tsx` is the current primary app screen and renders the voice controls/event log.
- `use-voice.ts` owns microphone capture, audio playback, Gemini Live connection, token request, and tool-call dispatch.
- `lib/agent-tools` maps Gemini function calls to local executors; current transaction/account behavior is mocked.
- `@wallet-bot/shared` is the frontend/backend contract for voice tool names and schemas.

## What This Diagram Shows

This diagram breaks the frontend into the main parts that are visible in `apps/web`:

- Bootstrap and routing: `main.tsx` creates the React app, wires providers, and mounts the router. `router.tsx` defines the split between public login routes and authenticated app routes.
- Auth layer: `auth-client.ts` configures Better Auth against the Convex site URL, while guards decide whether the user can access public or private routes.
- Layouts and pages: the current product surface is small. `/login` handles authentication and `/` renders the `Home` page with the live voice experience.
- Voice agent: `use-voice.ts` is the central frontend control module. It handles microphone permissions, device selection, audio worklets, Gemini Live connection lifecycle, token fetching through Convex, playback, logs, and function-call handling.
- UI components: reusable components live under `components/ui`, mostly following the shadcn-style component split.
- Workspace dependencies: the frontend imports the generated Convex API from `@wallet-bot/backend/api` and tool contracts from `@wallet-bot/shared`.

The most important dependency chain is `Home -> useVoice -> Convex action -> Gemini Live`. Auth is a separate chain through `authClient -> Better Auth HTTP routes`.

## Structure Opinion

For the current size, the frontend is understandable. The app has a clean separation between routing, auth, UI primitives, and the voice hook. The main concern is that `use-voice.ts` is doing a lot: audio capture, audio conversion, device management, session lifecycle, Gemini message handling, playback, logs, and tool-call dispatch all live in one file.

For a voice-first finance app, I would eventually split the voice feature into a feature folder, for example:

```text
src/features/voice/
  use-voice-session.ts
  audio-capture.ts
  audio-playback.ts
  gemini-live-client.ts
  voice-log.ts
  tool-dispatch.ts
```

That would make it easier to test and evolve the voice experience without turning one hook into the entire runtime.

I would also move `lib/agent-tools` closer to a domain boundary once real persistence exists. Right now the executors are frontend mocks, which is fine for proving the Gemini loop. For real expenses, these tools should call backend Convex mutations so the backend owns authorization, validation, idempotency, and writes.

The UI structure is fine, but as the app grows beyond the voice console, I would avoid putting all screens directly under `pages/` with shared state scattered across hooks. A feature-first split like `features/transactions`, `features/accounts`, `features/voice`, and `features/auth` would fit this product better once transaction history, account management, and analytics screens appear.
