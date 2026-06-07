# Reputation — Local Program

The per-user program: log into Audible, search for books, read reviews (every
one is saved locally), post your own reviews, and share collected reviews with
the central webserver.

> The webserver is **not** part of the first version. The "share" command targets
> it and will work once a server exists; everything else works standalone.

## Setup

```bash
cd local
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp config.example.yaml config.yaml   # then edit config.yaml with your details
```

## Run

```bash
python -m reputation_local --config config.yaml
```

On first run you may be prompted for Audible verification (CAPTCHA / OTP / CVF);
afterwards the session is cached to `auth.json` and reused.

## Design

Many small, single-responsibility ("dumb") classes. See
[`../docs/LOCAL_PROGRAM.md`](../docs/LOCAL_PROGRAM.md) for the full breakdown.

| Module | Class | Responsibility |
|---|---|---|
| `config_loader.py` | `ConfigLoader` | Read + validate `config.yaml`. |
| `config_models.py` | `AppConfig`, `AudibleCredentials`, `WebserverTarget` | Dumb settings holders. |
| `models.py` | `Book`, `Review` | Dumb data classes. |
| `review_id.py` | `make_review_id` | Stable de-dup id. |
| `audible_authenticator.py` | `AudibleAuthenticator` | Login + `auth.json` cache. |
| `audible_gateway.py` | `AudibleGateway` | The only class that knows Audible's API. |
| `book_searcher.py` | `BookSearcher` | Query → `Book`s. |
| `review_reader.py` | `ReviewReader` | ASIN → `Review`s, saving each. |
| `review_poster.py` | `ReviewPoster` | Submit a review to Audible. |
| `review_store.py` | `ReviewStore` | Read/write `reviews.json`. |
| `review_uploader.py` | `ReviewUploader` | Upload reviews to the webserver. |
| `app.py` | `App` | Orchestrator (wiring + sequencing). |
| `cli.py` | `CLI` | Menus/prompts. |
| `__main__.py` | — | Composition root / entry point. |

## Known gaps

- **Posting reviews** is not wired to a confirmed endpoint — the unofficial
  Audible API has no documented review-submission call, so `ReviewPoster.post`
  currently raises `NotImplementedError`. See `audible_gateway.py`.
- Audible endpoint paths / response-group field names are best-effort and live
  only in `AudibleGateway` / the searcher / the reader so they can be repaired in
  one place.
