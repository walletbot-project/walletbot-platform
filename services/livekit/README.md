# LiveKit on Dokploy

Self-hosted `livekit-server` for the Gaston voice agent. See
[docs/livekit-agent-transport.md](../../docs/livekit-agent-transport.md) for why
we self-host instead of using LiveKit Cloud.

One container. TURN is built into `livekit-server` and shares the room token
auth, so there is no coturn deployment and no second service to operate.

Deployed on the Walletbot Dokploy host (`152.67.53.236`, Oracle Cloud) as a
Compose service named `livekit-stack`.

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
| 3478 | UDP | yes | TURN/UDP |
| 5349 | TCP | no | TURN/TLS in plaintext. Traefik terminates TLS at `turn.walletbot.live:443` |
| 30000-30100 | UDP | yes | TURN relay allocations |

TURN/UDP is on 3478 rather than 443 because Dokploy's Traefik enables HTTP/3,
and QUIC already binds 443/UDP:

```yaml
websecure:
  address: :443
  http3:
    advertisedPort: 443
```

LiveKit fails to start if you put TURN/UDP there. Restrictive networks are still
covered by TURN/TLS on 443/TCP through the SNI router, which is the path that
matters when a network blocks UDP wholesale anyway.

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

Create a **Compose** service with compose path
`services/livekit/docker-compose.yml`. Set Compose Type to **Docker Compose**,
not Stack. Swarm ignores `network_mode: host`.

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
Traefik labels that a host-network container cannot satisfy. Step 5 replaces
that.

### 4. Open the firewall, both layers

On Oracle Cloud this is two separate firewalls and **both** block by default.
Missing either one produces a service that looks healthy and carries no media.

Cloud security list or NSG ingress:

```
7881/tcp   7882-7892/udp   3478/udp   30000-30100/udp
```

Host iptables, over SSH. The stock OCI ruleset rejects everything except 22, 80
and 443, including traffic arriving from Docker's bridge:

```bash
sudo iptables -I INPUT 1 -p tcp --dport 7881 -j ACCEPT
sudo iptables -I INPUT 1 -p udp --dport 3478 -j ACCEPT
sudo iptables -I INPUT 1 -p udp --dport 7882:7892 -j ACCEPT
sudo iptables -I INPUT 1 -p udp --dport 30000:30100 -j ACCEPT
sudo iptables -I INPUT 1 -s 172.17.0.0/16 -p tcp -m multiport --dports 7880,5349 -j ACCEPT
sudo netfilter-persistent save
```

That last rule is the one people miss. Traefik dials LiveKit across the Docker
bridge, and without it every request returns 502 with
`connect: no route to host` in the Traefik log. `no route to host` means an
iptables REJECT, not a missing listener.

While you have a root shell, the UDP receive buffer is worth raising.
`livekit-server` warns about it on every boot:

```bash
echo 'net.core.rmem_max=5000000' | sudo tee /etc/sysctl.d/60-livekit.conf
sudo sysctl --system
```

### 5. Install the Traefik config

Copy [traefik/livekit.yml](./traefik/livekit.yml) into Dokploy's dynamic config
directory, substituting the host address:

```bash
sed 's/__HOST_IP__/172.17.0.1/g' services/livekit/traefik/livekit.yml \
  > /etc/dokploy/traefik/dynamic/livekit.yml
```

Traefik watches that directory and reloads on its own. It requests certificates
for both hostnames through the same Let's Encrypt resolver Dokploy already uses,
including the TCP router, where it reads the domain off the `HostSNI` rule.

Use `172.17.0.1`, the `docker0` gateway. Dokploy's Traefik is attached to both
the default bridge (`172.17.0.2`) and `dokploy-network`, so that gateway is the
host from its point of view. Do **not** use the host's own private address: on
this box it is `10.0.0.57`, which collides with Docker Swarm's default ingress
network at `10.0.0.0/24` and is unroutable from inside a container.

## Verify

On boot `livekit-server` prints the exact TCP and UDP ports it expects to be
reachable. Check those against both firewalls first.

```bash
curl https://livekit.walletbot.live/          # expect OK
openssl s_client -connect turn.walletbot.live:443 -servername turn.walletbot.live </dev/null
```

Then run a real connection against https://livekit.io/connection-test with
`wss://livekit.walletbot.live` and a token generated from the key pair:

```bash
docker run --rm livekit/livekit-server create-join-token \
  --room test --identity tester \
  --api-key APIxxxxxxxxxxxx --api-secret your-generated-secret
```

To confirm the relay specifically, force TURN in the test page's ICE settings.
If media works direct but fails when relayed, the problem is 3478/UDP or the
`turn.walletbot.live` certificate, not the SFU.

## Debugging

**`livekit-server` exits 0 on every startup error.** Its `main()` prints the
error and falls off the end:

```go
if err := cmd.Run(context.Background(), os.Args); err != nil {
    fmt.Println(err)
}
```

So a crash-looping container with `Exited (0)` tells you nothing. The reason is
on stdout and nowhere else. Read the container logs before theorising.

**Config parsing is strict by default.** Unknown keys are a hard failure, so a
key copied from documentation for a different version stops the server dead.
Validate against the tag you are actually running, not `master`:

```bash
curl -s https://raw.githubusercontent.com/livekit/livekit/v1.9.1/config-sample.yaml
```

This bit us once already: `logging.use_json` is master's spelling, and v1.9.1
calls it `logging.json`.

## Not here yet

Redis is absent because a single node does not need it. Track egress does, and
it shares Redis with `livekit-server`, so adding audio export to GCS means
adding both a Redis service and `livekit-egress` to this stack.

Webhooks to the Convex ingest endpoint are also unconfigured. They go under a
`webhook:` block in the config body once the endpoint exists.
