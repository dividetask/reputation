"""BookSearcher — turn a search query into Book objects.

Maps the gateway's raw catalog response into dumb Book data classes. Field
names are best-effort against the unofficial API; mapping is defensive.
"""

from __future__ import annotations

from .audible_gateway import AudibleGateway
from .models import Book


class BookSearcher:
    def __init__(self, gateway: AudibleGateway) -> None:
        self._gateway = gateway

    def search(self, query: str) -> list[Book]:
        raw = self._gateway.search_products(query)
        return [self._to_book(p) for p in raw.get("products", [])]

    @staticmethod
    def _to_book(product: dict) -> Book:
        return Book(
            asin=product.get("asin", ""),
            title=product.get("title", ""),
            authors=[a.get("name", "") for a in product.get("authors", [])],
            narrators=[n.get("name", "") for n in product.get("narrators", [])],
        )
