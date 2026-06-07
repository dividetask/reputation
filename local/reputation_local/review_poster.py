"""ReviewPoster — submit one user-written review to Audible.

Builds the payload and delegates to the gateway. NOTE: the underlying gateway
``post_review`` is not yet wired to a confirmed endpoint (see AudibleGateway),
so calling ``post`` currently raises NotImplementedError.
"""

from __future__ import annotations

from .audible_gateway import AudibleGateway
from .models import Review
from .review_id import make_review_id


class ReviewPoster:
    def __init__(self, gateway: AudibleGateway) -> None:
        self._gateway = gateway

    def post(self, asin: str, rating: int, title: str, body: str) -> Review:
        payload = {"rating": rating, "title": title, "review_content": body}
        self._gateway.post_review(asin, payload)
        return Review(
            review_id=make_review_id(asin, reviewer="me", body=body),
            asin=asin,
            book_title="",
            body=body,
            rating=rating,
            title=title,
            reviewer="me",
            source="audible",
        )
