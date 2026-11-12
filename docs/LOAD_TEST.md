# DevPulse — Load test report (Phase 6, 2026-11-12)

**Tool:** `make loadtest` → `python -m app.scripts.loadtest` (asyncio + httpx; refuses non-local targets). Raw results: `docs/load-test/*.json`.

**Setup:** the Docker Compose stack on a MacBook (Docker: 8 CPUs, 4 GB RAM, shared with other local stacks — numbers are relative, not a capacity promise). API = uvicorn; Postgres 16 and Redis 7 in containers; 20 services, one ingest key per writer, batches of 500 metric points.

**Method:** 15 s per step. (1) ingestion at 1, 4, 8 and 16 concurrent writers; (2) the five main read endpoints, 2 readers each, while 4 writers keep ingesting; (3) time until the last ingested minute appears in the 1-minute rollups.

## Results

| Run | 1 writer | 4 writers | 8 writers | 16 writers | Read p95 under ingest | Rollup catch-up |
|---|---|---|---|---|---|---|
| 1. Baseline (1 process, executemany insert) | 17.7k pts/s · p95 68 ms | 27.0k · 196 ms | 28.9k · 323 ms | 19.8k · 711 ms | 295–382 ms | 52 s |
| 2. Batched insert (`INSERT … SELECT FROM unnest`) | **27.2k · 27 ms** | **47.1k · 90 ms** | 38.7k · 193 ms ¹ | 35.6k · 403 ms ¹ | 222–274 ms | **25 s** |
| 3. Batched insert + 4 API processes | 27.3k · 26 ms | **65.4k · 55 ms** ¹ | 39.1k · 312 ms ¹ | 40.5k · 523 ms ¹ | **104–216 ms** | **19 s** |

¹ Includes 429s from the per-ingest-key limit (1,200 requests/min ≈ 600k points/min per key), which is working as intended; keys were reused across steps, so later steps hit it sooner.

Read endpoints in run 3 (req/s · p95): overview 29.9 · 216 ms, services 43.1 · 110 ms, incidents 46.9 · 104 ms, metrics (6 h) 40.9 · 106 ms, sync feed 39.7 · 140 ms.

## What changed and why

- **Profiling** (pyinstrument, in-process) showed ~70% of an ingest request in the row-by-row `executemany` insert. `COPY` would be fastest but **Postgres rejects `COPY FROM` into tables with row-level security**, so the batch is now sent as arrays in one `INSERT … SELECT FROM unnest(…)`: +54% single-writer throughput, +63% peak, rollup lag halved.
- **Process count** is now configurable (`WEB_CONCURRENCY`); with 4 processes the API sustains ~65k points/s here and read latency under ingestion roughly halves.
- RLS (added in the same phase) is active in these runs' code path; its per-row check did not show up in the profile.

## Limits and next steps

- Ingestion beyond ~40k points/s on this machine is bounded by Postgres in a shared 4 GB VM; a real capacity test needs production-sized hardware.
- The alert-rule preview replays a rule with one query per 5-minute step (up to 289); fine for an admin action, but it should become one windowed query.
- Mobile performance profiling (Flutter DevTools, profile mode) needs a physical device — open.
- Render free tier: 0.1 CPU and 512 MB per service — staging is for correctness, not load.
