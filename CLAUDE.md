# CLAUDE.md — Project Guidelines

## Critical Rules

### Do not loop on errors — stop and explain

- If an approach fails twice, stop immediately. Do not retry the same strategy.
- Explain what went wrong, what was attempted, and suggest alternatives — let me decide how to proceed.
- Do not silently retry file operations, compilations, or code execution hoping for a different result.
- If a tool call or code execution returns an error, analyze the error before taking any further action.
- When stuck on a problem, present the situation clearly rather than burning through tokens on repeated attempts.

### Ask questions often

- Ask questions often especially when there is ambiguity or you believe I have made a mistake
- Ask questions in plain chat text, not via the `AskUserQuestion` / multiple-choice prompt tool. Do not use that tool in this project — write the question(s) as normal prose and wait for a reply.

### Stop after asking questions

- Whenever you have a question, or multiple questions, stop immediatly after asking them.

---

## Project Overview

**Reputation** is an Audible review-sharing system made of two cooperating programs:

1. **Local program** — runs on a user's machine. It reads Audible login
   credentials and settings from a YAML config file, logs into Audible, and lets
   the user search for books and read reviews. Every review it reads is saved
   locally to a JSON file. It can also connect to the webserver (URL/port from
   the same YAML file) and share every review it has downloaded from Audible.
   (Posting reviews back to Audible is not supported — the unofficial API is
   read-oriented and has no review-submission endpoint.)

2. **Webserver** — a central service that accepts uploaded Audible reviews from
   any number of local programs and lets viewers browse the collected reviews.
   Webservers also **federate**: each one keeps a list of peer webservers and
   periodically syncs reviews with them, so the collection converges across the
   network.

> **Build order.** Version 1 is the **local program only** — it is scaffolded in
> [`local/`](local/). The **webserver is deferred**: we get the local program
> working correctly before coding the server. Webserver docs are the target
> design, not yet implemented.

See `docs/` for the full documentation set:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — system overview, data flow, the full class breakdown for both programs.
- [`docs/LOCAL_PROGRAM.md`](docs/LOCAL_PROGRAM.md) — local program design, classes, and responsibilities.
- [`docs/WEBSERVER.md`](docs/WEBSERVER.md) — webserver design, endpoints, and classes.
- [`docs/CONFIGURATION.md`](docs/CONFIGURATION.md) — the YAML config file format.
- [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md) — the `Review`/`Book` schemas and on-disk JSON formats.

---

## Tech Stack (recommended default)

> These choices are documented defaults, not hard requirements. Raise it with me
> before changing them.

- **Language:** Python 3.10+ end-to-end (both programs).
- **Audible access:** the [`mkb79/Audible`](https://github.com/mkb79/Audible)
  library — a low-level Python client for Audible's non-public API. It provides
  the `Authenticator` (login + encrypted `auth.json` session cache) and
  `Client` / `AsyncClient` (thin `get()`/`post()` over catalog endpoints).
- **Webserver:** FastAPI + Uvicorn.
- **Config:** YAML (`PyYAML`).
- **Local storage:** plain JSON files (no database for the local program).
- **HTTP client (local → server):** `httpx` or `requests`.

> **Note on Audible:** there is no official public reviews API. All Audible
> access goes through the unofficial `mkb79/Audible` client, which is inherently
> more fragile than a supported API and subject to Audible/Amazon Terms of
> Service. Treat endpoint shapes as best-effort and keep the Audible-specific
> code isolated behind a thin gateway class so it can be repaired in one place.

---

## Core Design Principle: keep every class dumb

This is the most important architectural rule for this project.

- **One responsibility per class.** A class loads config, *or* talks to Audible,
  *or* stores JSON, *or* renders the CLI — never several of these.
- **Dumb means small and predictable.** Classes hold simple data or perform one
  narrow job. They should be easy to read top-to-bottom with no hidden state.
- **No god objects.** There is no single class that "does everything." An
  orchestrator/app class only *wires together* and *calls* the small classes; it
  contains no business logic of its own beyond sequencing.
- **Separate data from behavior.** `Book` and `Review` are dumb data
  holders (dataclasses / Pydantic models) with no I/O and no network calls.
- **Isolate the outside world.** Anything that touches Audible, the filesystem,
  or the network lives behind its own narrow class (a "gateway"/"client"/"store")
  so the rest of the code depends on a small, stable interface.
- **Constructor injection.** Pass collaborators in via the constructor rather
  than constructing them inside a class. This keeps classes dumb and testable.

When in doubt, split a class in two rather than letting one grow smart.

---

## Repository Layout (planned)

```
reputation/
├── CLAUDE.md
├── README.md
├── .gitignore
├── docs/
│   ├── ARCHITECTURE.md
│   ├── LOCAL_PROGRAM.md
│   ├── WEBSERVER.md
│   ├── CONFIGURATION.md
│   └── DATA_MODEL.md
├── local/                       # the local program (SCAFFOLDED)
│   ├── README.md
│   ├── requirements.txt
│   ├── config.example.yaml
│   └── reputation_local/        # one small "dumb" class per module
│       ├── __main__.py          # composition root / entry point
│       ├── config_loader.py     # ConfigLoader
│       ├── config_models.py     # AppConfig, AudibleCredentials, WebserverTarget
│       ├── models.py            # Book, Review
│       ├── review_id.py         # make_review_id (dedup key)
│       ├── audible_authenticator.py
│       ├── audible_gateway.py   # the only class that knows Audible's API
│       ├── book_searcher.py
│       ├── review_reader.py     # saves every review it reads
│       ├── review_store.py      # reviews.json
│       ├── review_uploader.py
│       ├── app.py               # orchestrator
│       └── cli.py
└── server/                      # the webserver (DEFERRED — not started)
    └── ...
```

> The `local/` source tree is scaffolded (runnable structure; Audible endpoint
> shapes are best-effort). The `server/` tree is **not** started yet — see the
> build order above.

---

## Conventions

- Keep Audible-specific knowledge in one gateway class; the rest of the code
  speaks in `Book`/`Review` objects, not raw Audible JSON.
- Never commit real credentials or a populated `auth.json`. Only commit
  `*.example.yaml` templates. Add `config.yaml` and `auth.json` to
  `.gitignore` when code lands.
- Reviews are content-addressed by a stable `review_id` (see
  [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md)) so the same review is never stored
  or uploaded twice.
