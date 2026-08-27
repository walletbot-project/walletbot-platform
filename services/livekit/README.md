# LiveKit on Dokploy

Self-hosted `livekit-server` for the Gaston voice agent. See
[docs/livekit-agent-transport.md](../../docs/livekit-agent-transport.md) for why
we self-host instead of using LiveKit Cloud.

One container. TURN is built into `livekit-server` and shares the room token
auth, so there is no coturn deployment and no second service to operate.

## Why host networking

The container runs with `network_mode: host`. WebRTC media is UDP, and Docker's
userland proxy adds a hop on every packet plus a NAT rewrite that ICE has to
work around. On the host network LiveKit binds the machine's ports directly and
sees real source addresses.

The cost is that Dokploy's Traefik cannot discover the container through
`traefik.*` labels, because a host-network container has no address on
`dokploy-network`. TLS termination is wired up with a Traefik dynamic config
file instead ([traefik/livekit.yml](./traefik/livekit.yml)), which points at the
host by IP.

## Ports

| Port | Proto | Public | Purpose |
|---|---|---|---|
| 7880 | TCP | no | Signaling HTTP. Traefik fronts it at `wss://livekit.walletbot.live` |
| 7881 | TCP | yes | ICE/TCP fallback. Cannot sit behind a proxy or TLS |
| 7882-7892 | UDP | yes | ICE/UDP mux, one port per vCPU |
| 443 | UDP | yes | TURN/UDP. Traefik only binds 443/TCP, so this is free |
| 5349 | TCP | no | TURN/TLS in plaintext. Traefik terminates TLS at `turn.walletbot.live:443` |
| 30000-30100 | UDP | yes | TURN relay allocations |

TURN over 443 is the point of this layout. Argentine mobile carriers sit behind
CGNAT and a real share of connections fail without a relay reachable on a port
that restrictive networks leave open.

Traefik keeps 443/TCP for HTTPS and LiveKit takes 443/UDP for TURN. They do not
collide unless Dokploy enables HTTP/3, which it does not by default. If you
ever turn HTTP/3 on, move `turn.udp_port` off 443 first.

## Setup

### 1. DNS

Two A records at the server IP:

- `livekit.walletbot.live` for signaling
- `turn.walletbot.live` for TURN

They have to be separate hostnames. Traefik routes TCP by SNI, so a TCP router
on the signaling hostname would swallow its HTTPS traffic.

### 2. Generate API keys

```bash
docker run --rm livekit/livekit-server generate-keys
```

Keep the pair. Convex needs it to mint join tokens and the agent worker needs it
to register.

### 3. Create the Dokploy service

Create a **Compose** service, provider Git, pointing at this repo with compose
path `services/livekit/docker-compose.yml`. Set Compose Type to **Docker
Compose**, not Stack. Swarm ignores `network_mode: host`.

Fill in the environment from [.env.example](./.env.example):

```
LIVEKIT_KEYS=APIxxxxxxxxxxxx: your-generated-secret
LIVEKIT_TURN_DOMAIN=turn.walletbot.live
LIVEKIT_SIGNAL_PORT=7880
LIVEKIT_LOG_LEVEL=info
```

`LIVEKIT_KEYS` is the one secret here and the only value the compose file does
not carry. LiveKit reads it directly and it overrides whatever the config body
declares, which is why no key material is committed.

Do not add a domain in the Dokploy UI for this service. Dokploy would write
Traefik labels that a host-network container cannot satisfy. Step 4 replaces
that.

### 4. Install the Traefik config

Copy [traefik/livekit.yml](./traefik/livekit.yml) into Dokploy's dynamic config
directory, substituting the host IP:

```bash
HOST_IP=$(hostname -I | awk '{print $1}')
sed "s/__HOST_IP__/$HOST_IP/g" services/livekit/traefik/livekit.yml \
  > /etc/dokploy/traefik/dynamic/livekit.yml
```

Traefik watches that directory and reloads on its own. It requests certificates
for both hostnames through the same Let's Encrypt resolver Dokploy already uses,
including the TCP router, where it reads the domain off the `HostSNI` rule.

Use the machine's own IP rather than a Docker bridge gateway. LiveKit binds
`0.0.0.0` on the host, so the real IP is reachable from Traefik's container no
matter which network it sits on.

### 5. Open the firewall

Cloud firewalls block UDP by default, and this is the most common reason a
deployment looks healthy and produces silence. Open at the provider level:

```
7881/tcp
7882-7892/udp
443/udp
30000-30100/udp
```

7880 and 5349 stay closed to the internet. Traefik reaches them over the host.

## Verify

On boot `livekit-server` prints the exact TCP and UDP ports it expects to be
reachable. Check those against the firewall first.

Then run a real connection against https://livekit.io/connection-test with
`wss://livekit.walletbot.live` and a token generated from the key pair:

```bash
docker run --rm livekit/livekit-server create-join-token \
  --room test --identity tester \
  --api-key APIxxxxxxxxxxxx --api-secret your-generated-secret
```

To confirm the relay specifically, force TURN in the test page's ICE settings.
If media works direct but fails when relayed, the problem is 443/UDP or the
`turn.walletbot.live` certificate, not the SFU.

## Not here yet

Redis is absent because a single node does not need it. Track egress does, and
it shares Redis with `livekit-server`, so adding audio export to GCS means
adding both a Redis service and `livekit-egress` to this stack.

Webhooks to the Convex ingest endpoint are also unconfigured. They go under a
`webhook:` block in the config body once the endpoint exists.
