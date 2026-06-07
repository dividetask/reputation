# Local Program

The local program runs on a user's machine. It logs into Audible using
credentials from a YAML config file and lets the user:

- **search** for books,
- **read** reviews for a book (saving every review it reads to a local JSON file),
- **post** their own reviews to Audible, and
- **share** all the reviews it has collected by uploading them to the webserver.

It is built from many small, **dumb** classes (one responsibility each). The
sections below describe each class: its job, what it depends on, and the methods
it is expected to expose. Method signatures are illustrative — the contract
matters more than the exact names.

> Stack: Python 3.10+, [`mkb79/Audible`](https://github.com/mkb79/Audible) for
> Audible access, `PyYAML` for config, `httpx`/`requests` for the upload client.

---

## 1. Configuration classes

### `ConfigLoader`
**Responsibility:** read and validate `config.yaml`, produce an `AppConfig`.
Does nothing else. Fails loudly with a clear message if required fields are
missing.

```python
class ConfigLoader:
    def __init__(self, path: str): ...
    def load(self) -> "AppConfig": ...   # reads YAML, validates, builds AppConfig
```

### `AppConfig`
**Responsibility:** a dumb, immutable holder for all settings. No I/O. It groups
the smaller value objects below.

```python
@dataclass(frozen=True)
class AppConfig:
    audible: "AudibleCredentials"
    webserver: "WebserverTarget"
    reviews_path: str        # where reviews.json lives
    auth_cache_path: str     # where auth.json lives
```

### `AudibleCredentials`
**Responsibility:** dumb holder for Audible login fields.

```python
@dataclass(frozen=True)
class AudibleCredentials:
    username: str
    password: str
    marketplace: str   # e.g. "us", "uk", "de" (locale/country code)
```

### `WebserverTarget`
**Responsibility:** dumb holder for the webserver address.

```python
@dataclass(frozen=True)
class WebserverTarget:
    url: str
    port: int

    @property
    def base_url(self) -> str: ...   # e.g. "http://host:port"
```

See [`CONFIGURATION.md`](CONFIGURATION.md) for the full YAML format.

---

## 2. Audible access classes

### `AudibleAuthenticator`
**Responsibility:** turn credentials into an authenticated Audible session, and
cache/restore that session via `auth.json`. Wraps `audible.Authenticator`.

```python
class AudibleAuthenticator:
    def __init__(self, credentials: AudibleCredentials, auth_cache_path: str): ...
    def authenticate(self) -> "audible.Authenticator":
        # if auth.json exists -> Authenticator.from_file(...)
        # else -> log in with username/password/marketplace, then to_file(...)
        ...
```

> The underlying library may require interactive steps (CAPTCHA, OTP, CVF) on
> first login. Keep that interaction here, behind this one class.

### `AudibleGateway`
**Responsibility:** the **only** class that knows Audible's API shape. A thin
wrapper over `audible.Client` exposing just the raw calls the app needs. It
returns raw response data; converting to `Book`/`Review` happens in the
searcher/reader, keeping this class dumb.

```python
class AudibleGateway:
    def __init__(self, auth: "audible.Authenticator"): ...
    def search_products(self, query: str, num_results: int = 20) -> dict:
        # client.get("1.0/catalog/products", keywords=query, num_results=..., response_groups="product_desc,product_attrs")
        ...
    def get_product_reviews(self, asin: str) -> dict:
        # client.get(f"1.0/catalog/products/{asin}", response_groups="reviews,rating")
        ...
    def post_review(self, asin: str, payload: dict) -> dict:
        # NOT wired: the unofficial API has no confirmed review-submission
        # endpoint. Raises NotImplementedError until one is confirmed.
        ...
```

> Endpoint paths/response groups are best-effort against the unofficial API and
> may need adjustment. They live **only** here so repairs are one-file changes.
> **Posting reviews** in particular is unverified — Audible review submission
> normally happens through the website, so `post_review` currently raises
> `NotImplementedError` (the rest of the pipeline is wired and ready).

---

## 3. Data classes

### `Book`
**Responsibility:** dumb holder for a catalog item. No I/O.

```python
@dataclass(frozen=True)
class Book:
    asin: str
    title: str
    authors: list[str]
    narrators: list[str] = field(default_factory=list)
```

### `Review`
**Responsibility:** dumb holder for one review. No I/O. Full field list and the
`review_id` rule are in [`DATA_MODEL.md`](DATA_MODEL.md).

```python
@dataclass(frozen=True)
class Review:
    review_id: str       # stable id (see DATA_MODEL.md)
    asin: str
    book_title: str
    author: str | None
    rating: int | None
    title: str | None
    body: str
    reviewer: str | None
    created_at: str | None   # ISO-8601 if known
    source: str = "audible"
```

---

## 4. Operation classes (one Audible action each)

### `BookSearcher`
**Responsibility:** turn a search query into `Book` objects.

```python
class BookSearcher:
    def __init__(self, gateway: AudibleGateway): ...
    def search(self, query: str) -> list[Book]: ...   # maps gateway dict -> Book[]
```

### `ReviewReader`
**Responsibility:** turn a book/ASIN into `Review` objects. **Saves every review
it reads** by handing them to the `ReviewStore`. This "save on read" rule is a
core requirement, and it lives here.

```python
class ReviewReader:
    def __init__(self, gateway: AudibleGateway, store: "ReviewStore"): ...
    def read(self, asin: str) -> list[Review]:
        raw = self.gateway.get_product_reviews(asin)
        reviews = self._to_reviews(raw)
        self.store.add_many(reviews)   # persist every review read
        return reviews
```

### `ReviewPoster`
**Responsibility:** submit one user-written review to Audible.

```python
class ReviewPoster:
    def __init__(self, gateway: AudibleGateway): ...
    def post(self, asin: str, rating: int, title: str, body: str) -> Review: ...
```

---

## 5. Persistence & sharing classes

### `ReviewStore`
**Responsibility:** the **only** local class that touches `reviews.json`. Reads,
appends (de-duplicated by `review_id`), and lists reviews.

```python
class ReviewStore:
    def __init__(self, path: str): ...
    def add_many(self, reviews: list[Review]) -> int: ...   # returns # newly added
    def all(self) -> list[Review]: ...
```

> De-dup by `review_id` means re-reading the same book never bloats the file.
> See the on-disk format in [`DATA_MODEL.md`](DATA_MODEL.md).

### `ReviewUploader`
**Responsibility:** share collected reviews — read everything from the store and
POST it to the webserver. Knows the upload endpoint; knows nothing about Audible.

> The webserver is deferred (v2), so this class has nothing to talk to yet. It is
> included now because sharing is a local-program responsibility and the upload
> contract is already defined in [`WEBSERVER.md`](WEBSERVER.md).

```python
class ReviewUploader:
    def __init__(self, target: WebserverTarget, store: ReviewStore, http=...): ...
    def upload_all(self) -> "UploadResult": ...   # POST store.all() to {base_url}/reviews
```

---

## 6. Interface & orchestration

### `CLI`
**Responsibility:** render menus/prompts and collect input. No business logic —
it only calls into `App` and prints results.

```python
class CLI:
    def __init__(self, app: "App"): ...
    def run(self) -> None: ...   # menu loop: search / read / post / share / quit
```

### `App`
**Responsibility:** orchestrator. Wires the classes together and sequences the
operations the CLI asks for. Contains no business logic of its own beyond
sequencing.

```python
class App:
    def __init__(self, searcher, reader, poster, uploader): ...
    def search(self, query: str) -> list[Book]: ...
    def read_reviews(self, asin: str) -> list[Review]: ...
    def post_review(self, asin, rating, title, body) -> Review: ...
    def share(self) -> "UploadResult": ...
```

### Entry point (composition root)
A small `main()` is the only place that constructs concrete objects and injects
them — keeping every class above dumb and unaware of how it was built.

```python
def main():
    config = ConfigLoader("config.yaml").load()
    auth = AudibleAuthenticator(config.audible, config.auth_cache_path).authenticate()
    gateway = AudibleGateway(auth)
    store = ReviewStore(config.reviews_path)
    app = App(
        searcher=BookSearcher(gateway),
        reader=ReviewReader(gateway, store),
        poster=ReviewPoster(gateway),
        uploader=ReviewUploader(config.webserver, store),
    )
    CLI(app).run()
```

---

## 7. Typical run

1. `main()` loads config, authenticates, wires the app.
2. User picks **search** → `App.search` → `BookSearcher` → list of `Book`s.
3. User picks a book → **read** → `App.read_reviews` → `ReviewReader` fetches and
   **saves every review** to `reviews.json`.
4. User picks **post** → writes a review → `ReviewPoster` submits it to Audible.
5. User picks **share** → `ReviewUploader` uploads everything in the store to the
   webserver.
