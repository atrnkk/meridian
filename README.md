# Meridian

Self-hosted analytics for Roblox games.

```
Roblox game servers --HTTPS POST--> Caddy --> ClickHouse <-- Grafana
```

Game servers insert batches straight into ClickHouse through Caddy. Every game shares one
`meridian.events` table, told apart by `game_id`. Game-specific fields live in the JSON
`props` column and get broken out per game with materialized views.

## Setup

You need Docker. Copy `.env.example` to `.env`, fill in the passwords, and set
`MERIDIAN_URL`:

- **On your own PC:** `MERIDIAN_URL=http://localhost`. Studio playtests can send to it,
  but live Roblox servers can't.
- **On a server:** `MERIDIAN_URL=https://<hostname>`, with the hostname's DNS pointing at
  the server and ports 80 and 443 open. Caddy gets the HTTPS certificate on first start.

```sh
docker compose up -d
```

Then:

- Grafana: `<MERIDIAN_URL>/`, user `admin`. The dashboards are under
  Dashboards › dashboards › shared.
- Ingest: `<MERIDIAN_URL>/ingest` (POST only, always as the `ingest` user).
- Admin SQL shell: `docker compose exec clickhouse clickhouse-client`.
- Stop: `docker compose down`. Add `-v` to also delete all data.

## Environment variables

| Variable | Used for |
| --- | --- |
| `MERIDIAN_URL` | Address Caddy serves, e.g. `http://localhost` or `https://meridian.example.com`. |
| `CLICKHOUSE_INGEST_PASSWORD` | Insert-only ClickHouse user that game servers use. |
| `CLICKHOUSE_GRAFANA_PASSWORD` | Read-only ClickHouse user that Grafana uses. |
| `GRAFANA_ADMIN_PASSWORD` | Grafana `admin` login. |

After changing `.env`, run `docker compose up -d`.

## Connecting a game

1. Put the `Meridian` ModuleScript in ServerScriptService and require it once from a
   server script: `require(game:GetService("ServerScriptService").Meridian)`.
2. In Studio's Game Settings › Security, turn on **Allow HTTP Requests**.
3. Add two secrets:
   - `meridian_url`: `<MERIDIAN_URL>/ingest`
   - `meridian_key`: the value of `CLICKHOUSE_INGEST_PASSWORD`

   For Studio playtests, add them under Game Settings › Security › Local Secrets. For live
   servers, add them on the experience's Creator Hub page (Configure › Secrets). Restrict
   each secret's domain to the host in `MERIDIAN_URL`. Without HTTP or the secrets, the
   module warns once and does nothing.

The module tracks joins/leaves, spawns, deaths, position samples, and purchases on its
own. Use `Meridian.Track(eventName, props)` for anything else. Per-game hooks go in a
`MeridianHooks` folder in ServerScriptService: each ModuleScript there returns a
function that receives `Track`.

## Dashboards

The dashboards in `dashboards/shared/` work for every game: pick the game at the top. Until a
game sends events, the picker says "No data yet".

- **Overview**: live players and servers, sessions, deaths, purchases, top events, and a
  position heatmap. Refreshes every 5 seconds.
- **Players**: new vs returning players, DAU/WAU/MAU, stickiness, session length,
  concurrent players, day 1/7/30 retention by cohort, and top players.
- **Monetization**: purchases, buyers, conversion, repeat buyers, time to first purchase,
  and purchases by item, buyer, session minute, and hour.
- **Events**: any event, including custom ones from `Meridian.Track`, broken down by each of
  its props, with the latest raw events.
- **Map**: per place, heatmaps of player traffic and deaths, the deadliest spots, and a
  height profile of time spent vs deaths.

Grafana won't save changes to these dashboards. Edit the JSON files instead; Grafana
reloads them within 30 seconds.

## Adding a game

1. Copy `games/example` to `games/<name>`.
2. In `views.sql`, set the game's `game.GameId`, add its name to `meridian.games`, and write
   the views you need. Use `IF NOT EXISTS` so the file can be re-run.
3. Run `./apply-games.sh` (on Windows, from Git Bash).
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
