# Webserver

The webserver is the central hub. It does two things:

- **Accepts uploaded reviews** from any number of local programs.
- **Lets viewers browse** the pooled reviews.

It holds no Audible credentials and never talks to Audible — it only receives
already-collected `Review` objects and serves them back. Like the local program,
it is built from small, **dumb** classes (one responsibility each).

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

### `create_app()`
**Responsibility:** wiring/factory. Build `ServerConfig`, the repository, the
service, and register the controllers. No logic beyond composition.

```python
def create_app(config: ServerConfig | None = None) -> FastAPI:
    config = config or ServerConfig()
    repo = ReviewRepository(config.store_path)
    service = ReviewService(repo)
    app = FastAPI()
    app.include_router(UploadController(service).router)
    app.include_router(BrowseController(service).router)
    return app
```

---

## 2. Endpoints

| Method | Path | Purpose | Used by |
|---|---|---|---|
| `POST` | `/reviews` | Upload a batch of reviews | Local program (`ReviewUploader`) |
| `GET` | `/reviews` | Browse reviews (filter by `asin`, paginate) | Viewers |
| `GET` | `/reviews/{review_id}` | Fetch one review | Viewers |
| `GET` | `/books` | List books that have reviews (optional) | Viewers |
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

## 4. Why this split (dumb classes)

- **Controllers** only translate HTTP ↔ objects.
- **`ReviewService`** holds the only real logic (dedup/validate) in one place.
- **`ReviewRepository`** is the single storage boundary, so JSON → SQLite/Postgres
  is a one-class change.
- **`create_app()`** is pure wiring — no god object.

---

## 5. Open questions

- **Upload authentication.** Whether uploads require an API key (and how the local
  program supplies it from `config.yaml`) is not yet decided. `ServerConfig` and
  `WebserverTarget` leave room for it.
- **Viewer UI.** This document specifies a JSON API. Whether viewers browse via a
  built-in HTML UI or a separate frontend is undecided; either consumes the same
  `GET /reviews` endpoints.
- **Storage backend.** JSON file is the documented default for simplicity.
