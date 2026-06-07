# Webserver

> **Status: deferred.** The webserver is **not** part of the first version. We
> are getting the local program working correctly first, then building this. The
> design below is the target spec, not implemented code.

The webserver is a review hub. It does three things:

- **Accepts uploaded reviews** from any number of local programs.
- **Lets viewers browse** the pooled reviews.
- **Federates with other webservers** — it keeps a list of peer webservers and
  periodically syncs reviews with them, so the full collection converges across
  the network of servers (see §6).

It holds no Audible credentials and never talks to Audible — it only receives
already-collected `Review` objects, serves them back, and exchanges them with
peer servers. Like the local program, it is built from small, **dumb** classes
(one responsibility each).

> Stack: Python 3.10+, FastAPI + Uvicorn. Storage default is a JSON-file-backed
> repository, swappable for a database behind `ReviewRepository`.

---

## 1. Classes

### `ServerConfig`
**Responsibility:** read server settings (bind host/port, store path, optional
upload API key). No logic beyond loading.

```python
@dataclass(frozen=True)
class ServerConfig:
    host: str = "0.0.0.0"
    port: int = 8000
    store_path: str = "server_reviews.json"
    upload_api_key: str | None = None   # optional; see "Open questions"
    peers: list[str] = field(default_factory=list)   # other webserver base URLs
    sync_interval_seconds: int = 300                  # how often to sync with peers
```

### `Review`
**Responsibility:** dumb data/validation model for a review on the wire and at
rest. In FastAPI this is a Pydantic model so malformed uploads are rejected
automatically. Fields match the local program's `Review` — see
[`DATA_MODEL.md`](DATA_MODEL.md).

### `ReviewRepository`
**Responsibility:** the **only** class that touches storage. Persists and fetches
reviews; de-dups by `review_id`. Knows nothing about HTTP.

```python
class ReviewRepository:
    def __init__(self, store_path: str): ...
    def add_many(self, reviews: list[Review]) -> int: ...     # new rows added
    def list(self, asin: str | None = None,
             limit: int = 50, offset: int = 0) -> list[Review]: ...
    def get(self, review_id: str) -> Review | None: ...
```

### `ReviewService`
**Responsibility:** the small amount of real logic — validate and de-duplicate
incoming reviews, then hand them to the repository. Sits between controllers and
the repository so controllers stay dumb.

```python
class ReviewService:
    def __init__(self, repo: ReviewRepository): ...
    def ingest(self, reviews: list[Review]) -> "IngestResult": ...   # dedup + store
    def browse(self, asin: str | None, limit: int, offset: int) -> list[Review]: ...
```

### `UploadController`
**Responsibility:** HTTP entry point for uploads. Translates the request into
`Review` objects and calls `ReviewService.ingest`. No business logic.

```
POST /reviews
  body: { "reviews": [ <Review>, ... ] }
  -> 200 { "received": N, "added": M, "duplicates": K }
```

### `BrowseController`
**Responsibility:** HTTP entry point for browsing. Calls `ReviewService.browse`
and returns the results. No business logic.

```
GET /reviews?asin=<asin>&limit=<n>&offset=<n>   -> list of reviews
GET /reviews/{review_id}                        -> single review (404 if missing)
GET /books                                       -> distinct books that have reviews (optional)
GET /health                                      -> { "status": "ok" }
```

### `PeerRegistry`
**Responsibility:** the dumb list of peer webservers this server syncs with.
Holds peer base URLs (seeded from `ServerConfig.peers`); add/list/remove only.
No HTTP, no logic.

```python
class PeerRegistry:
    def __init__(self, peers: list[str]): ...
    def all(self) -> list[str]: ...
    def add(self, base_url: str) -> None: ...
    def remove(self, base_url: str) -> None: ...
```

### `PeerClient`
**Responsibility:** the only class that makes outbound HTTP calls to a peer.
Pulls a peer's reviews (and optionally pushes ours). Knows the peer endpoint
shape; knows nothing about storage.

```python
class PeerClient:
    def __init__(self, http=...): ...
    def fetch_since(self, peer_base_url: str, since: str | None) -> list[Review]:
        # GET {peer}/reviews?since=<cursor> — incremental pull
        ...
```

### `PeerSyncService`
**Responsibility:** the federation logic in one place. For each peer, pull
reviews via `PeerClient` and hand them to `ReviewService.ingest` (which de-dups
by `review_id`). Returns a per-peer summary. No HTTP or storage of its own.

```python
class PeerSyncService:
    def __init__(self, peers: PeerRegistry, peer_client: PeerClient,
                 reviews: ReviewService): ...
    def sync_once(self) -> "SyncResult": ...   # one pass over all peers
```

### `PeerSyncScheduler`
**Responsibility:** the only class that knows about time. Calls
`PeerSyncService.sync_once()` every `sync_interval_seconds` (e.g. via a
background task / asyncio loop). No sync logic of its own.

```python
class PeerSyncScheduler:
    def __init__(self, sync: PeerSyncService, interval_seconds: int): ...
    async def run(self) -> None: ...   # loop: sync_once(), sleep(interval)
```

### `create_app()`
**Responsibility:** wiring/factory. Build `ServerConfig`, the repository, the
service, the federation classes, and register the controllers + the background
sync loop. No logic beyond composition.

```python
def create_app(config: ServerConfig | None = None) -> FastAPI:
    config = config or ServerConfig()
    repo = ReviewRepository(config.store_path)
    service = ReviewService(repo)

    peers = PeerRegistry(config.peers)
    peer_sync = PeerSyncService(peers, PeerClient(), service)
    scheduler = PeerSyncScheduler(peer_sync, config.sync_interval_seconds)

    app = FastAPI()
    app.include_router(UploadController(service).router)
    app.include_router(BrowseController(service).router)
    app.include_router(PeerController(peers, peer_sync).router)
    app.on_event("startup")(lambda: asyncio.create_task(scheduler.run()))
    return app
```

### `PeerController`
**Responsibility:** HTTP entry point for federation — lets operators inspect
peers and trigger a sync, and (optionally) lets peers register themselves.
No business logic.

```
GET  /peers              -> list known peers
POST /peers              -> register a peer { "base_url": "..." }
POST /peers/sync         -> trigger PeerSyncService.sync_once() now
```

---

## 2. Endpoints

| Method | Path | Purpose | Used by |
|---|---|---|---|
| `POST` | `/reviews` | Upload a batch of reviews | Local program (`ReviewUploader`) |
| `GET` | `/reviews` | Browse reviews (filter by `asin`, paginate; `since` cursor for peer pulls) | Viewers, peer servers |
| `GET` | `/reviews/{review_id}` | Fetch one review | Viewers |
| `GET` | `/books` | List books that have reviews (optional) | Viewers |
| `GET` | `/peers` | List known peer servers | Ops, peers |
| `POST` | `/peers` | Register a peer server | Ops, peers |
| `POST` | `/peers/sync` | Trigger a peer sync now | Ops |
| `GET` | `/health` | Liveness check | Ops |

See [`DATA_MODEL.md`](DATA_MODEL.md) for request/response bodies.

---

## 3. Request / response examples

**Upload (local program → server):**

```http
POST /reviews
Content-Type: application/json

{
  "reviews": [
    {
      "review_id": "audible:B0XXATOMIC:c0ffee...",
      "asin": "B0XXATOMIC",
      "book_title": "Project Hail Mary",
      "author": "Andy Weir",
      "rating": 5,
      "title": "Loved it",
      "body": "Could not stop listening.",
      "reviewer": "alex",
      "created_at": "2026-05-01T12:00:00Z",
      "source": "audible"
    }
  ]
}
```

```json
{ "received": 1, "added": 1, "duplicates": 0 }
```

**Browse (viewer → server):**

```http
GET /reviews?asin=B0XXATOMIC&limit=20&offset=0
```

```json
[
  { "review_id": "audible:B0XXATOMIC:c0ffee...", "asin": "B0XXATOMIC", "rating": 5, "...": "..." }
]
```

---

## 4. Federation — syncing with other webservers

Each webserver tracks a set of **peer webservers** and periodically syncs with
them so the pooled collection converges across the whole network. A review
uploaded to *any* server eventually reaches *every* server.

```
   ┌──────────┐  pull /reviews?since=…  ┌──────────┐
   │ Server A │ ──────────────────────▶ │ Server B │
   │          │ ◀────────────────────── │          │
   └────┬─────┘                         └────┬─────┘
        │            both also sync with     │
        └──────────────▶ ┌──────────┐ ◀──────┘
                         │ Server C │
                         └──────────┘
```

How it works:

1. `PeerSyncScheduler` fires every `sync_interval_seconds`.
2. For each peer in the `PeerRegistry`, `PeerSyncService` uses `PeerClient` to
   **pull** that peer's reviews (incrementally, via a `since` cursor on
   `GET /reviews`).
3. Pulled reviews go through `ReviewService.ingest`, which **de-dups by
   `review_id`** — the same content-addressed id used everywhere — so re-syncing
   never creates duplicates and the operation is idempotent.

Design notes:

- **Pull-based** keeps each server in control of its own writes and makes
  dedup trivial. (A push variant could reuse the existing `POST /reviews`.)
- Because `review_id` is content-derived (see [`DATA_MODEL.md`](DATA_MODEL.md)),
  convergence is eventual and conflict-free — order of syncing doesn't matter.
- All federation knowledge is isolated in `PeerRegistry` / `PeerClient` /
  `PeerSyncService` / `PeerSyncScheduler`, each dumb and single-purpose.

---

## 5. Why this split (dumb classes)

- **Controllers** only translate HTTP ↔ objects.
- **`ReviewService`** holds the only real logic (dedup/validate) in one place,
  and is reused by both uploads and peer sync.
- **`ReviewRepository`** is the single storage boundary, so JSON → SQLite/Postgres
  is a one-class change.
- **Federation** is split four ways: who the peers are (`PeerRegistry`), talking
  to a peer (`PeerClient`), the sync logic (`PeerSyncService`), and the timing
  (`PeerSyncScheduler`).
- **`create_app()`** is pure wiring — no god object.

---

## 6. Open questions

- **Upload authentication.** Whether uploads require an API key (and how the local
  program supplies it from `config.yaml`) is not yet decided. `ServerConfig` and
  `WebserverTarget` leave room for it.
- **Peer trust & auth.** How peers authenticate to each other, and whether peer
  membership is static (config) or self-registering via `POST /peers`, is not yet
  decided.
- **Sync cursor.** The exact `since` cursor (timestamp vs. monotonic sequence) for
  incremental pulls is to be specified.
- **Viewer UI.** This document specifies a JSON API. Whether viewers browse via a
  built-in HTML UI or a separate frontend is undecided; either consumes the same
  `GET /reviews` endpoints.
- **Storage backend.** JSON file is the documented default for simplicity.
