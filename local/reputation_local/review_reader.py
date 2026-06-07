"""ReviewReader — turn a book/ASIN into Review objects, saving every one.

This class owns the core "save on read" requirement: every review it reads is
handed to the ReviewStore before being returned. Mapping from the raw Audible
response is defensive because the field names are best-effort.
"""

from __future__ import annotations

from .audible_gateway import AudibleGateway
from .models import Review
from .review_id import make_review_id
from .review_store import ReviewStore


class ReviewReader:
    def __init__(self, gateway: AudibleGateway, store: ReviewStore) -> None:
        self._gateway = gateway
        self._store = store

    def read(self, asin: str) -> list[Review]:
        raw = self._gateway.get_product_reviews(asin)
        product = raw.get("product", raw)  # response may or may not nest "product"
        reviews = [
            self._to_review(asin, product, r)
            for r in self._extract_review_dicts(product)
        ]
        self._store.add_many(reviews)  # persist EVERY review read
        return reviews

    @staticmethod
    def _extract_review_dicts(product: dict) -> list[dict]:
        # The reviews list has appeared under a few keys across API versions.
        for key in ("customer_reviews", "reviews", "editorial_reviews"):
            value = product.get(key)
            if isinstance(value, list):
                return value
        return []

    @staticmethod
    def _to_review(asin: str, product: dict, raw: dict) -> Review:
        body = raw.get("review_content") or raw.get("content") or raw.get("body") or ""
        reviewer = raw.get("author_name") or raw.get("reviewer_name") or raw.get("author")
        created_at = raw.get("submission_date") or raw.get("date") or raw.get("created_at")
        rating = raw.get("rating") or raw.get("overall_rating")
        return Review(
            review_id=make_review_id(
                asin,
                native_id=raw.get("guid") or raw.get("id"),
                reviewer=reviewer,
                created_at=created_at,
                body=body,
            ),
            asin=asin,
            book_title=product.get("title", ""),
            body=body,
            author=_first_author(product),
            rating=int(rating) if rating is not None else None,
            title=raw.get("title"),
            reviewer=reviewer,
            created_at=created_at,
            source="audible",
        )


def _first_author(product: dict) -> str | None:
    authors = product.get("authors") or []
    if authors:
        return authors[0].get("name")
    return None
