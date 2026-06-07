"""make_review_id — derive a stable, unique id for a review.

A single small helper so the de-duplication rule lives in exactly one place.
See ../docs/DATA_MODEL.md (section 4) for the rule.
"""

from __future__ import annotations

import hashlib


def make_review_id(
    asin: str,
    native_id: str | None = None,
    reviewer: str | None = None,
    created_at: str | None = None,
    body: str = "",
) -> str:
    """Return ``audible:<asin>:<id>``.

    Uses Audible's native review id when available; otherwise a sha256 of the
    review's stable content so the same review always maps to the same id.
    """
    if native_id:
        return f"audible:{asin}:{native_id}"
    fingerprint = f"{reviewer}|{created_at}|{body}".encode("utf-8")
    return f"audible:{asin}:{hashlib.sha256(fingerprint).hexdigest()}"
