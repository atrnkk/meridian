# Meridian

Self-hosted analytics for Roblox games.

```
Roblox game servers --HTTPS POST--> Caddy --> ClickHouse <-- Grafana
```

Game servers insert batches straight into ClickHouse through Caddy. Every game shares one
`meridian.events` table, told apart by `game_id`. Game-specific fields live in the JSON
`props` column and get broken out per game with materialized views.

## Setup

You need a machine with Docker and a DNS name pointing at it, with ports 80 and 443 open.

```sh
cp .env.example .env   # then fill it in
docker compose up -d
```

Caddy fetches an HTTPS certificate for `MERIDIAN_DOMAIN` on first start. Then:

- Grafana: `https://<MERIDIAN_DOMAIN>/`, user `admin`. The Overview dashboard is under
  Dashboards › dashboards › shared.
- Ingest: `https://<MERIDIAN_DOMAIN>/ingest` (POST only, always as the `ingest` user).
- Admin SQL shell: `docker compose exec clickhouse clickhouse-client`.

## Environment variables

| Variable | Used for |
| --- | --- |
| `MERIDIAN_DOMAIN` | Public hostname. Caddy serves HTTPS for it. |
| `CLICKHOUSE_INGEST_PASSWORD` | Insert-only ClickHouse user that game servers use. |
| `CLICKHOUSE_GRAFANA_PASSWORD` | Read-only ClickHouse user that Grafana uses. |
| `GRAFANA_ADMIN_PASSWORD` | Grafana `admin` login. |

After changing a password, run `docker compose up -d`.

## Connecting a game

1. Put the `Meridian` ModuleScript in ServerScriptService and require it once from a
   server script: `require(game:GetService("ServerScriptService").Meridian)`.
2. In Studio's Game Settings › Security, turn on **Allow HTTP Requests**.
3. Add two secrets on the experience's Creator Hub page (Configure › Secrets), with the
   domain restricted to `MERIDIAN_DOMAIN`:
   - `meridian_url`: `https://<MERIDIAN_DOMAIN>/ingest`
   - `meridian_key`: the value of `CLICKHOUSE_INGEST_PASSWORD`

   For Studio playtests, add the same two under Game Settings › Security › Local Secrets.
   Without HTTP or the secrets, the module warns once and does nothing.

The module tracks joins/leaves, spawns, deaths, position samples, and purchases on its
own. Use `Meridian.Track(eventName, props)` for anything else. Per-game hooks go in a
`MeridianHooks` folder in ServerScriptService: each ModuleScript there returns a
function that receives `Track`.

## Adding a game

1. Copy `games/example` to `games/<name>`.
2. In `views.sql`, set the game's `game.GameId`, add its name to `meridian.games`, and write
   the views you need. Use `IF NOT EXISTS` so the file can be re-run.
3. Run `./apply-games.sh`.
4. Put dashboard JSON files in `games/<name>/dashboards/`. Grafana picks them up within
   30 seconds, in a folder matching the path.

Views run as the admin who created them (see `clickhouse/config.xml`), so the insert-only
ingest user can feed them. If a view fails, the insert into `events` still succeeds; the
error shows up in `system.query_views_log`.

## Notes

- Events are kept for 90 days (TTL on `events`).
- `clickhouse/init/00_core.sql` only runs when the ClickHouse volume is first created.
  Apply later schema changes by hand in the admin SQL shell.
- The ingest user has a per-minute quota in `clickhouse/users.xml`. Raise it as your
  games grow.
- Studio playtests send real events. Their `server_id` is empty.
