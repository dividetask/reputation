# Configuration

The local program is configured entirely through a single **YAML file**
(default: `config.yaml`). It contains the Audible login credentials, the
webserver address, and local file paths.

> **Never commit a real `config.yaml`.** Commit only a `config.example.yaml`
> template, and add `config.yaml` and `auth.json` to `.gitignore` once code
> lands. The credentials are your real Audible/Amazon login.

---

## 1. Example `config.yaml`

```yaml
# Audible login credentials and marketplace.
audible:
  username: "you@example.com"     # Amazon/Audible account email
  password: "your-password"       # Amazon/Audible password
  marketplace: "us"               # locale / country code: us, uk, de, fr, ca, au, jp, in, it, es, br

# Where the central webserver lives. The local program uploads reviews here.
webserver:
  url: "http://reviews.example.com"   # scheme + host (no port)
  port: 8000

# Local file paths.
storage:
  reviews_path: "reviews.json"    # every review the program reads is saved here
  auth_cache_path: "auth.json"    # cached Audible session (created on first login)
```

---

## 2. Field reference

### `audible`
| Field | Type | Required | Description |
|---|---|---|---|
| `username` | string | yes | Amazon/Audible account email. |
| `password` | string | yes | Amazon/Audible password. |
| `marketplace` | string | yes | Audible marketplace / country code (e.g. `us`, `uk`, `de`). Determines which regional Audible store is used. |

### `webserver`
| Field | Type | Required | Description |
|---|---|---|---|
| `url` | string | yes | Scheme + host of the webserver, e.g. `http://reviews.example.com`. |
| `port` | integer | yes | Webserver port, e.g. `8000`. |

> `url` + `port` combine into the base URL the local program posts to, e.g.
> `http://reviews.example.com:8000/reviews`.

### `storage`
| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `reviews_path` | string | no | `reviews.json` | File where every read review is saved. |
| `auth_cache_path` | string | no | `auth.json` | Cached Audible session, so you don't re-login every run. |

---

## 3. How the config is consumed

`ConfigLoader.load()` reads this file and validates it, producing an immutable
`AppConfig` made of small value objects:

```
config.yaml
   └─▶ ConfigLoader.load()
         └─▶ AppConfig
               ├─ AudibleCredentials(username, password, marketplace)
               ├─ WebserverTarget(url, port)
               ├─ reviews_path
               └─ auth_cache_path
```

No other class reads the YAML directly — they receive typed objects. See
[`LOCAL_PROGRAM.md`](LOCAL_PROGRAM.md).

---

## 4. First-run login note

On the **first** login, the underlying [`mkb79/Audible`](https://github.com/mkb79/Audible)
library may require interactive verification (CAPTCHA, one-time password, or
"CVF" email/SMS code). After a successful login the session is written to
`auth_cache_path` (`auth.json`), and later runs reuse it without prompting.

---

## 5. Open question — upload auth

If the webserver later requires an API key for uploads, it will be added here,
e.g.:

```yaml
webserver:
  url: "http://reviews.example.com"
  port: 8000
  api_key: "..."     # not yet specified — see WEBSERVER.md "Open questions"
```

This is **not** implemented/decided yet.
