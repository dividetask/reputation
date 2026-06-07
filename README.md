# reputation

**Reputation** is an Audible review-sharing system. It collects book reviews
from Audible and pools them on a central server so they can be browsed in one
place.

It has two parts:

- A **local program** that logs into Audible (credentials supplied via a YAML
  config file), lets you search for books, read reviews, and post your own
  reviews. It saves every review it reads to a local JSON file and can upload
  everything it has collected to the webserver.
- A **webserver** that accepts uploaded reviews from any number of local
  programs and lets viewers browse the pooled collection.

```
┌─────────────────┐        login / search / read / post        ┌─────────┐
│  Local program  │  ───────────────────────────────────────▶  │ Audible │
│  (per user)     │  ◀───────────────────────────────────────  │   API   │
└────────┬────────┘             reviews + catalog               └─────────┘
         │  saves every review it reads → reviews.json (local)
         │
         │  uploads collected reviews (HTTP)
         ▼
┌─────────────────┐        browse pooled reviews        ┌──────────────────┐
│   Webserver     │  ◀───────────────────────────────   │     Viewers      │
└─────────────────┘                                     └──────────────────┘
```

## Status

Greenfield — **documentation only** so far. No application code yet.

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — system overview, data flow, and the full class breakdown.
- [`docs/LOCAL_PROGRAM.md`](docs/LOCAL_PROGRAM.md) — the local program.
- [`docs/WEBSERVER.md`](docs/WEBSERVER.md) — the webserver.
- [`docs/CONFIGURATION.md`](docs/CONFIGURATION.md) — the YAML config file.
- [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md) — review/book schemas and on-disk formats.
- [`CLAUDE.md`](CLAUDE.md) — project guidelines and design principles.

## Tech stack (recommended default)

Python 3.10+ end-to-end. The local program uses the
[`mkb79/Audible`](https://github.com/mkb79/Audible) library for Audible access;
the webserver uses FastAPI. See [`CLAUDE.md`](CLAUDE.md) for details.
