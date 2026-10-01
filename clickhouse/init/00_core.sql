-- Runs once, when the ClickHouse volume is first created.

CREATE DATABASE IF NOT EXISTS meridian;

-- Every event from every game. Game-specific fields go in `props` (a JSON object)
-- and are broken out per game by materialized views in games/*/views.sql.
CREATE TABLE IF NOT EXISTS meridian.events
(
    ts         DateTime64(3, 'UTC'),
    game_id    UInt64,                  -- game.GameId
    place_id   UInt64,                  -- game.PlaceId
    server_id  String,                  -- game.JobId (empty in Studio)
    user_id    UInt64,                  -- 0 for events not tied to a player
    session_id String,                  -- one per player join, empty if no player
    event      LowCardinality(String),
    x          Float32,
    y          Float32,
    z          Float32,
    props      String DEFAULT '{}'
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(ts)
ORDER BY (game_id, event, ts)
TTL toDateTime(ts) + INTERVAL 90 DAY;

-- Display names for Grafana. Each game's views.sql inserts its own row.
CREATE TABLE IF NOT EXISTS meridian.games
(
    game_id UInt64,
    name    String
)
ENGINE = ReplacingMergeTree
ORDER BY game_id;
