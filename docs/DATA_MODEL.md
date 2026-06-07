# Data Model

This document defines the shared shapes used across both programs: the `Book`
and `Review` objects, the local `reviews.json` file format, and the webserver
store format. Keeping these identical on both sides is what lets the local
program upload directly to the webserver.

---

## 1. `Review`

The central object of the whole system.

| Field | Type | Required | Description |
|---|---|---|---|
| `review_id` | string | yes | **Stable, unique** id (see §4). Used for de-duplication everywhere. |
| `asin` | string | yes | Audible product id the review is for. |
| `book_title` | string | yes | Title of the book, denormalized for easy browsing. |
| `author` | string \| null | no | Book author, if known. |
| `rating` | integer \| null | no | Star rating, typically 1–5. |
| `title` | string \| null | no | The review's headline/title. |
| `body` | string | yes | The review text. |
| `reviewer` | string \| null | no | Display name of the reviewer, if available. |
| `created_at` | string \| null | no | When the review was written (ISO-8601), if known. |
| `source` | string | yes | Where it came from. Default `"audible"`. |

### Example

```json
{
  "review_id": "audible:B0XXATOMIC:c0ffeed00dface...",
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
```

---

## 2. `Book`

Used while searching the catalog. Not necessarily persisted on its own — the
fields needed for browsing are denormalized onto each `Review`
(`asin`, `book_title`, `author`).

| Field | Type | Required | Description |
|---|---|---|---|
| `asin` | string | yes | Audible product id. |
| `title` | string | yes | Book title. |
| `authors` | string[] | yes | Authors. |
| `narrators` | string[] | no | Narrators. |

---

## 3. On-disk formats

### Local program — `reviews.json`

Every review the local program **reads** is appended here (de-duped by
`review_id`). A simple, flat list of `Review` objects:

```json
{
  "version": 1,
  "reviews": [
    { "review_id": "audible:B0XXATOMIC:c0ffee...", "asin": "B0XXATOMIC", "...": "..." },
    { "review_id": "audible:B0YYWIDGET:beef...",   "asin": "B0YYWIDGET", "...": "..." }
  ]
}
```

`ReviewStore` is the only class that reads/writes this file.

### Webserver — store

The webserver's `ReviewRepository` stores the same `Review` shape. With the
default JSON-file backend the format mirrors `reviews.json`. With a database
backend, each field becomes a column; `review_id` is the primary key.

---

## 4. `review_id` — the de-duplication key

`review_id` must be **stable** (the same review always produces the same id) and
**unique**, because it is used to avoid storing or uploading the same review
twice — locally and on the server.

**Rule:** if Audible exposes a native review id, use it:

```
"audible:<asin>:<audible_review_id>"
```

Otherwise, derive a deterministic id by hashing the stable content:

```
"audible:<asin>:" + sha256(f"{reviewer}|{created_at}|{body}").hexdigest()
```

Because the id is content-derived, re-reading the same book never creates
duplicates, and two users who upload the same Audible review collapse to one row
on the server.

---

## 5. Shared shape, two sides

```
Audible API ──▶ ReviewReader ──▶ Review ──▶ ReviewStore (reviews.json)
                                            │
                                            ▼  (upload, same JSON shape)
                                  Webserver ReviewRepository ──▶ store
                                            │
                                            ▼
                                       Viewers browse
```

The `Review` JSON is identical end-to-end, so no translation layer is needed
between the local program and the webserver.
