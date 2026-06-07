"""ReviewUploader — share collected reviews with the webserver.

Reads everything from the store and POSTs it to the webserver's /reviews
endpoint. Knows the upload contract; knows nothing about Audible.

NOTE: the webserver is not part of the first version, so this class has nothing
to talk to yet. It is included because sharing is a local-program responsibility
and the upload contract is already defined in ../docs/WEBSERVER.md.
"""

from __future__ import annotations

from dataclasses import dataclass

from .config_models import WebserverTarget
from .review_store import ReviewStore


@dataclass(frozen=True)
class UploadResult:
    received: int
    added: int
    duplicates: int


class ReviewUploader:
    def __init__(self, target: WebserverTarget, store: ReviewStore) -> None:
        self._target = target
        self._store = store

    def upload_all(self) -> UploadResult:
        import httpx  # lazy import so the package imports without the dependency

        reviews = [r.to_dict() for r in self._store.all()]
        response = httpx.post(
            f"{self._target.base_url}/reviews",
            json={"reviews": reviews},
            timeout=30.0,
        )
        response.raise_for_status()
        body = response.json()
        return UploadResult(
            received=body.get("received", len(reviews)),
            added=body.get("added", 0),
            duplicates=body.get("duplicates", 0),
        )
