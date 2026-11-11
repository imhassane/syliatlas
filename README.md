# Syli Atlas

African economies, every figure sourced: IMF country profiles, regions,
sovereign ratings, stock exchanges. Phoenix 1.8, SQLite, Oban.

## Local development

```sh
mix setup                              # deps, database, assets
mix phx.server                         # http://localhost:4000
mix precommit                          # before every commit: compile, format, tests
```

Emails go to `/dev/mailbox` by default. To see them as they will look in a
real inbox, run Mailpit and send over SMTP:

```sh
docker compose up -d mailpit
MAILER_ADAPTER=smtp mix phx.server     # read them at http://localhost:8025
```

Market data: `MANSA_FAKE=true` serves fictitious figures in MansaAPI's shapes
(`SyliAtlas.Market.Sources.MansaFake`), so development never spends the daily
quota of the real key. Pages then say the figures are fictitious.

Every variable read at boot is listed in `.env.example`.

## Git workflow (Git Flow, no pre-production)

| Branch | From | Merged into | Deployed to |
|---|---|---|---|
| `main` | — | — | Railway **production**: every commit is a tagged release (`v0.1.0`) |
| `develop` | `main` | — | Railway **development**: integration of finished features |
| `feat/<name>` (or `fix/`, `docs/`) | `develop` | `develop` | — |
| `release/<version>` | `develop` | `main` and `develop` | production, once merged into `main` |
| `hotfix/<version>` | `main` | `main` and `develop` | production, once merged into `main` |

- Never commit directly to `main` or `develop`; merge with `--no-ff` so each
  feature, release and hotfix stays visible in the history.
- A feature is merged into `develop` once `mix precommit` passes, then its
  branch is deleted. `develop` deploys to development on every push.
- A release: `git checkout -b release/0.2.0 develop`, fixes only, then merge
  into `main`, tag `v0.2.0`, merge back into `develop`, push `main`,
  `develop` and the tag. Production deploys `main` on push.
- A hotfix: `git checkout -b hotfix/0.2.1 main`, the fix, then merge into
  `main` (tag `v0.2.1`) and into `develop`.
- Versions follow `MAJOR.MINOR.PATCH`; `mix.exs` carries the same version.

## Environments (Railway project « overflowing-perception »)

| | development | production |
|---|---|---|
| Branch | `develop` | `main` |
| Emails | SMTP to the `mailpit` service (`SMTP_HOST=mailpit.railway.internal`), read on its Railway domain (basic auth `MP_UI_AUTH`) | Resend (`RESEND_API_KEY`, sending domain verified at Resend) |
| Database | its own volume (`/data`) | its own volume (`/data`) |
| Market data | `MANSA_FAKE=true`: fictitious figures, no MansaAPI call | MansaAPI (`STOCK_EXCHANGE_API_KEY`) |
| Passkeys | bound to its own `PHX_HOST` | bound to the production `PHX_HOST` |

Both set `FIRST_ADMIN_EMAIL`: only that address can become the first
administrator. A passkey registered on one environment does not work on the
other (different host).

## Public API and Cloudflare

The documentation is at `/fr/api` and `/en/api`; `/api/v1` lists the routes.
Each answer carries `server-timing`; the server time of each route is kept
per hour (`api_timings`, hourly probe `ApiTimingWorker`) and shown on the
page against a 10 ms budget at the 99th percentile. Requests are limited per
visitor address (60 a minute, `RATE_LIMIT_PER_MINUTE`); behind Cloudflare the
address is `CF-Connecting-IP`, believed only from Cloudflare's ranges
(`SyliAtlasWeb.ClientIp`).

Cloudflare, once per zone (production only):

1. **Cache rule** (Caching > Cache Rules): when hostname equals the site's
   host, URI path starts with `/api/v1/`, and URI path is neither
   `/api/v1/search` nor `/api/v1/version` → eligible for cache; Edge TTL by
   status code: 200 for 1 day, nothing else cached; Browser TTL: respect origin.
2. **Purge token** (My Profile > API Tokens): permission Zone > Cache Purge,
   on this zone only. Set `CLOUDFLARE_ZONE_ID` and `CLOUDFLARE_API_TOKEN` on
   the production service: every publication then queues `CachePurgeWorker`,
   which purges the prefix `<host>/api/v1/`.
3. Check: `curl -sI https://<host>/api/v1/areas | grep cf-cache-status`
   answers `MISS` then `HIT`.

