"""ReviewStore — the only local class that touches reviews.json.

Reads, appends (de-duplicated by review_id), and lists Review objects. The
on-disk format is ``{"version": 1, "reviews": [ ... ]}`` (see DATA_MODEL.md).
"""

from __future__ import annotations

import json
import os

from .models import Review

_VERSION = 1


class ReviewStore:
    def __init__(self, path: str) -> None:
        self._path = path

    def all(self) -> list[Review]:
        """Return every stored review."""
        return [Review.from_dict(d) for d in self._read()["reviews"]]

    def add_many(self, reviews: list[Review]) -> int:
        """Append reviews, skipping any whose review_id is already stored.

        Returns the number of newly added reviews.
        """
        data = self._read()
        existing_ids = {r["review_id"] for r in data["reviews"]}
        added = 0
        for review in reviews:
            if review.review_id in existing_ids:
                continue
            data["reviews"].append(review.to_dict())
            existing_ids.add(review.review_id)
            added += 1
        if added:
            self._write(data)
        return added

    def _read(self) -> dict:
        if not os.path.exists(self._path):
            return {"version": _VERSION, "reviews": []}
        with open(self._path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        data.setdefault("version", _VERSION)
        data.setdefault("reviews", [])
        return data

    def _write(self, data: dict) -> None:
        with open(self._path, "w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2, ensure_ascii=False)
