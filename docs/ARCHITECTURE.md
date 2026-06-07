# Architecture

This document describes the whole **Reputation** system: the two programs, how
data flows between them, and the full class breakdown. Each class is intended to
be **dumb** — one responsibility, small, predictable (see the design principle in
[`../CLAUDE.md`](../CLAUDE.md)).

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
                        │               WEBSERVER                  │
   HTTP uploads ──────▶ │  UploadController ─▶ ReviewService ──┐    │
                        │                                      ▼    │
   HTTP browse  ◀────── │  BrowseController  ◀─ ReviewRepository ─▶ reviews store
                        │                                           │
                        │  ServerConfig, create_app() (wiring)      │
                        └──────────────────────────────────────────┘
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

## 5. Class Breakdown — Webserver

Details in [`WEBSERVER.md`](WEBSERVER.md).

| Class | Single responsibility |
|---|---|
| `ServerConfig` | Read server settings (bind host/port, store path). |
| `Review` | Dumb data/validation model for an incoming/stored review. |
| `ReviewRepository` | Persist + fetch reviews from the store. The only class that touches storage. |
| `ReviewService` | De-duplicate and validate reviews before they are stored. |
| `UploadController` | HTTP endpoint(s) for receiving uploaded reviews. |
| `BrowseController` | HTTP endpoint(s) for browsing reviews. |
| `create_app()` | Wiring/factory: build the app and connect controllers to the service. |

## 6. Why this split (dumb classes)

- The **gateway** is the only place that knows Audible's quirky, unofficial API.
  If Audible changes, you fix one class.
- **Searchers/readers/posters** each do exactly one Audible operation and speak
  in `Book`/`Review` objects, so they are trivial to read and test.
- **Stores/repositories** are the only classes that touch disk, so persistence
  can change (JSON → DB) without touching business logic.
- **Controllers** only translate HTTP ↔ objects; the **service** holds the small
  amount of real logic (dedup/validation).
- **`App` / `create_app()`** contain no logic beyond wiring and sequencing — no
  god objects.

## 7. Out of scope / open questions

- **Webserver storage backend.** Documented default is a JSON-file-backed
  repository for simplicity; swappable for SQLite/Postgres behind
  `ReviewRepository` without touching the rest.
- **Authentication between local program and server.** Not yet specified (e.g.
  an upload API key in the YAML). Flagged for a future decision.
- **Audible Terms of Service.** Access is via the unofficial API; fragility and
  ToS considerations apply. See [`../CLAUDE.md`](../CLAUDE.md).
