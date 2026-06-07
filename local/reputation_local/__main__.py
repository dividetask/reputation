"""Composition root for the local program.

The only place that constructs concrete objects and injects them, keeping every
other class dumb and unaware of how it was built.

Run with:  python -m reputation_local --config config.yaml
"""

from __future__ import annotations

import argparse
import sys

from .app import App
from .audible_authenticator import AudibleAuthenticator
from .audible_gateway import AudibleGateway
from .book_searcher import BookSearcher
from .cli import CLI
from .config_loader import ConfigError, ConfigLoader
from .review_reader import ReviewReader
from .review_store import ReviewStore
from .review_uploader import ReviewUploader


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="reputation_local")
    parser.add_argument("--config", default="config.yaml", help="Path to config.yaml")
    args = parser.parse_args(argv)

    try:
        config = ConfigLoader(args.config).load()
    except ConfigError as exc:
        print(f"Config error: {exc}", file=sys.stderr)
        return 2

    auth = AudibleAuthenticator(config.audible, config.auth_cache_path).authenticate()
    gateway = AudibleGateway(auth)
    store = ReviewStore(config.reviews_path)

    app = App(
        searcher=BookSearcher(gateway),
        reader=ReviewReader(gateway, store),
        uploader=ReviewUploader(config.webserver, store),
    )
    CLI(app).run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
