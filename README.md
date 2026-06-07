# reputation

**Reputation** is an Audible review-sharing system. It collects book reviews
from Audible and pools them on a central server so they can be browsed in one
place.

It has two parts:

- A **local program** that logs into Audible (credentials supplied via a YAML
  config file) and lets you search for books and read reviews. It saves every
  review it reads to a local JSON file and can upload everything it has collected
  to the webserver.
- A **webserver** that accepts uploaded reviews from any number of local
  programs and lets viewers browse the pooled collection. Webservers also
  federate — each tracks peer webservers and periodically syncs reviews with
  them so the collection converges across the network.

```
┌─────────────────┐          login / search / read            ┌─────────┐
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

- **Local program** — scaffolded in [`local/`](local/) (runnable class structure;
  Audible endpoint shapes are best-effort against the unofficial API).
- **Webserver** — **deferred.** We are getting the local program working
  correctly first. Its design (including webserver-to-webserver federation) is
  documented but not yet built.

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
