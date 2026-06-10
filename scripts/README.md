# Scripts

Compose files and helpers for standing up the home-lab Docker stack.

## Files

| File | Purpose |
|---|---|
| `docker-compose-core.yml` | Creates `media-net` + `db-net` networks, runs NPM and Portainer. **Run this first.** |
| `docker-compose-example-service.yml` | Template for attaching any new service to the shared networks. |
| `.env.example` | Required environment variables. Copy to `.env` and fill in before running. |

> `.env` is excluded from git via `.gitignore` — it may contain sensitive paths.

---

## Docker Network Architecture

Two named bridge networks with defined subnets. NPM holds a **static IP on both**
so proxy rules stay stable across restarts.

```
172.21.0.0/16 — media-net (web-facing services)
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│  nginxproxmgr  172.21.0.15   ──▶  http://nextcloud:80         │
│  (NPM)                        ──▶  http://portainer:9000       │
│                               ──▶  http://plex:32400           │
│                               ──▶  http://<any-container>:<port>│
│                                                                │
│  portainer     172.21.0.10                                     │
│  nextcloud     172.21.0.x                                      │
│  plex          172.21.0.x                                      │
│  …                                                             │
└────────────────────────────────────────────────────────────────┘

172.20.0.0/16 — db-net (backend / internal only)
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│  nginxproxmgr  172.20.0.15   (can proxy to db-facing services) │
│  postgres      172.20.0.x    ← shared DB for many services     │
│  app-db        172.20.0.x    ← service-specific DBs            │
│  …                                                             │
└────────────────────────────────────────────────────────────────┘
```

Services that only need a web frontend → `media-net` only.  
Services that need a database → both networks.  
Database containers → `db-net` only (never reachable via NPM).

---

## Quickstart

```bash
# 1. Set up environment variables
cp .env.example .env
nano .env   # fill in PUID, PGID, TZ, USERDIR

# 2. Create config directories
mkdir -p ${USERDIR}/docker/nginxproxmgr/{data,letsencrypt}
mkdir -p ${USERDIR}/docker/shared

# 3. Bring up NPM + Portainer (also creates the shared networks)
docker compose -f docker-compose-core.yml up -d

# 4. Open the NPM admin UI (LAN / Tailscale only — never expose to internet)
#    http://<docker-server-tailscale-ip>:81
#    Default login: admin@example.com / changeme  ← change immediately

# 5. Add your other stacks — they attach to the same networks via external: true
docker compose -f docker-compose-<service>.yml up -d
```

---

## Adding a new service behind NPM

1. Copy `docker-compose-example-service.yml` as a starting point
2. Declare `media-net` (and optionally `db-net`) as `external: true`
3. Use `expose` instead of `ports` — the container should not be reachable directly from the host
4. Optionally assign a static IP in the `172.21.0.x` range to keep NPM proxy rules stable
5. In the NPM admin UI, add a proxy host:
   - **Domain:** `myservice.yourdomain.com`
   - **Forward hostname:** container name or static IP
   - **Forward port:** internal port
   - **SSL:** request a Let's Encrypt certificate

---

## Volume path convention

All service config/data follows this pattern:

```
${USERDIR}/docker/
├── nginxproxmgr/
│   ├── data/
│   └── letsencrypt/
├── shared/
├── nextcloud/
├── plex/
└── <service>/
```

`USERDIR` is set in `.env` (typically `/home/youruser`).
