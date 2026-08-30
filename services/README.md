# services

Deployment definitions for infrastructure we run ourselves, outside Convex and
outside the app builds. Each subdirectory is one Dokploy service: a compose
file, the environment it expects, and whatever Traefik or host configuration it
needs.

These are not part of the pnpm workspace and nothing here is built by CI. They
are imported by Dokploy directly from this repo by compose path.

| Service | Path | What it is |
|---|---|---|
| LiveKit | [livekit/](./livekit) | Self-hosted SFU and TURN for the Gaston voice agent |
