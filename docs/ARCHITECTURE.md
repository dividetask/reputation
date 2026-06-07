# Architecture

This document describes the whole **Reputation** system: the two programs, how
data flows between them, and the full class breakdown. Each class is intended to
be **dumb** — one responsibility, small, predictable (see the design principle in
[`../CLAUDE.md`](../CLAUDE.md)).

> **Build order.** Version 1 is the **local program only** (now scaffolded in
> [`../local/`](../local)). The **webserver is deferred** — we get the local
> program working correctly first. The webserver sections below are the target
> design. When built, webservers also **federate**: each one tracks peer
> webservers and periodically syncs reviews with them (see §5 and
> [`WEBSERVER.md`](WEBSERVER.md)).

## 1. System Overview

```
                        ┌──────────────────────────────────────────┐
                        │              LOCAL PROGRAM               │
                        │                                          │
   config.yaml ───────▶ │  ConfigLoader ─▶ AppConfig               │
                        │                                          │
                        │  AudibleAuthenticator ─▶ AudibleGateway  │ ◀──▶ Audible API
                        │       │            │            │        │      (mkb79/Audible)
                        │  BookSearcher  ReviewReader  ReviewPoster│
                        │       │            │                     │
                        │       ▼            ▼                     │
                        │     Book         Review (data classes)   │
                        │                    │                     │
                        │              ReviewStore ───▶ reviews.json (local)
                        │                    │                     │
                        │              ReviewUploader ─────────────┼──▶ Webserver
                        │                                          │     (HTTP)
                        │  CLI ─▶ App (orchestrator, wires above)  │
                        └──────────────────────────────────────────┘

                        ┌──────────────────────────────────────────┐
                        │           WEBSERVER (deferred)           │
   HTTP uploads ──────▶ │  UploadController ─▶ ReviewService ──┐    │
                        │                                      ▼    │
   HTTP browse  ◀────── │  BrowseController  ◀─ ReviewRepository ─▶ reviews store
                        │                          ▲                │
                        │  PeerSyncScheduler ─▶ PeerSyncService ─┐  │
                        │       (every N s)         │            │  │
                        │  ServerConfig, create_app() (wiring)   │  │
                        └────────────────────────────────────────┼──┘
                                                                  ▼
                                            ◀── pull/push reviews ──▶ peer webservers
```

## 2. Data Flow

1. **Startup.** The local program loads `config.yaml` (Audible credentials,
   webserver URL/port, file paths) into an `AppConfig`.
2. **Login.** `AudibleAuthenticator` logs into Audible and produces an
   authenticated session, which it hands to the `AudibleGateway`. The session is
   cached to `auth.json` so subsequent runs skip the full login.
3. **Search.** The user searches for a book. `BookSearcher` asks the gateway and
   returns `Book` objects.
4. **Read reviews.** The user opens a book. `ReviewReader` fetches its reviews
   and returns `Review` objects. **Every review read is saved** by `ReviewStore`
   to the local `reviews.json`.
5. **Post a review.** The user writes a review. `ReviewPoster` submits it to
   Audible through the gateway.
6. **Share.** On request, `ReviewUploader` reads everything in `ReviewStore` and
   POSTs it to the webserver.
7. **Browse.** Viewers hit the webserver's browse endpoints; `BrowseController`
   asks the `ReviewRepository` and returns the pooled reviews.

## 3. The two programs at a glance

| | Local program | Webserver |
|---|---|---|
| Runs | On each user's machine | Centrally |
| Talks to | Audible + the webserver | Local programs + viewers |
| Persists | `reviews.json` (everything it reads) | Pooled review store |
| Config | `config.yaml` | `server` config (env/file) |
| Stack | Python + `mkb79/Audible` | Python + FastAPI |

## 4. Class Breakdown — Local Program

Each row is one dumb class with a single responsibility. Details in
[`LOCAL_PROGRAM.md`](LOCAL_PROGRAM.md).

| Class | Single responsibility |
|---|---|
| `ConfigLoader` | Read + validate `config.yaml`, produce an `AppConfig`. |
| `AppConfig` | Dumb holder for all settings (immutable). |
| `AudibleCredentials` | Dumb holder for username / password / marketplace. |
| `WebserverTarget` | Dumb holder for webserver URL + port. |
| `AudibleAuthenticator` | Log into Audible; load/save the `auth.json` session. |
| `AudibleGateway` | Thin wrapper over `audible.Client` get/post. **The only class that knows Audible's API shape.** |
| `Book` | Dumb data class: ASIN, title, author, etc. |
| `Review` | Dumb data class: the review fields (see `DATA_MODEL.md`). |
| `BookSearcher` | Turn a query into a list of `Book`s via the gateway. |
| `ReviewReader` | Turn a book/ASIN into a list of `Review`s via the gateway. |
| `ReviewPoster` | Submit one user-written `Review` to Audible via the gateway. |
| `ReviewStore` | Read/write `Review`s to the local `reviews.json`. |
| `ReviewUploader` | Send `Review`s from the store to the webserver over HTTP. |
| `CLI` | Render menus/prompts and collect user input. No business logic. |
| `App` | Orchestrator: wires the classes above and sequences calls. |

## 5. Class Breakdown — Webserver (deferred)

Details in [`WEBSERVER.md`](WEBSERVER.md). Not implemented yet — built after the
local program.

| Class | Single responsibility |
|---|---|
| `ServerConfig` | Read server settings (bind host/port, store path, peers, sync interval). |
| `Review` | Dumb data/validation model for an incoming/stored review. |
| `ReviewRepository` | Persist + fetch reviews from the store. The only class that touches storage. |
| `ReviewService` | De-duplicate and validate reviews before they are stored. |
| `UploadController` | HTTP endpoint(s) for receiving uploaded reviews. |
| `BrowseController` | HTTP endpoint(s) for browsing reviews. |
| `PeerRegistry` | Dumb list of peer webservers to sync with. |
| `PeerClient` | The only class that makes outbound HTTP calls to a peer. |
| `PeerSyncService` | Pull reviews from each peer and ingest them (dedup by `review_id`). |
| `PeerSyncScheduler` | The only class that knows about time: run a sync every N seconds. |
| `PeerController` | HTTP endpoint(s) to list/register peers and trigger a sync. |
| `create_app()` | Wiring/factory: build the app, connect controllers, start the sync loop. |

## 6. Why this split (dumb classes)

- The **gateway** is the only place that knows Audible's quirky, unofficial API.
  If Audible changes, you fix one class.
- **Searchers/readers/posters** each do exactly one Audible operation and speak
  in `Book`/`Review` objects, so they are trivial to read and test.
- **Stores/repositories** are the only classes that touch disk, so persistence
  can change (JSON → DB) without touching business logic.
- **Controllers** only translate HTTP ↔ objects; the **service** holds the small
  amount of real logic (dedup/validation).
- **Federation** is split four ways — `PeerRegistry` (who), `PeerClient` (how to
  talk), `PeerSyncService` (the sync logic, reusing `ReviewService` for dedup),
  and `PeerSyncScheduler` (when) — so no class grows smart.
- **`App` / `create_app()`** contain no logic beyond wiring and sequencing — no
  god objects.

### Federation flow (webserver ↔ webserver)

Once built, every server periodically pulls from its peers and converges:

1. `PeerSyncScheduler` fires every `sync_interval_seconds`.
2. `PeerSyncService` asks `PeerClient` to pull each peer's reviews (incrementally,
   via a `since` cursor on the peer's `GET /reviews`).
3. Pulled reviews are handed to `ReviewService.ingest`, which **de-dups by
   `review_id`** — the same content-addressed id used everywhere — so syncing is
   idempotent and the network of servers converges to the same collection.

## 7. Out of scope / open questions

- **Webserver storage backend.** Documented default is a JSON-file-backed
  repository for simplicity; swappable for SQLite/Postgres behind
  `ReviewRepository` without touching the rest.
- **Authentication between local program and server.** Not yet specified (e.g.
  an upload API key in the YAML). Flagged for a future decision.
- **Peer trust & sync cursor.** How peer servers authenticate to each other,
  whether membership is static or self-registering, and the exact `since` cursor
  for incremental pulls are all undecided. See [`WEBSERVER.md`](WEBSERVER.md).
- **Posting reviews to Audible.** The unofficial API has no confirmed
  review-submission endpoint, so `ReviewPoster`/`AudibleGateway.post_review` are
  scaffolded but raise `NotImplementedError` until an endpoint is confirmed.
- **Audible Terms of Service.** Access is via the unofficial API; fragility and
  ToS considerations apply. See [`../CLAUDE.md`](../CLAUDE.md).
