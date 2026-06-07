"""Dumb data classes shared across the program.

`Book` and `Review` hold data only. The `to_dict`/`from_dict` helpers are pure
transformations (no file or network I/O) used by the store and uploader.
See ../docs/DATA_MODEL.md for the field reference.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class Book:
    asin: str
    title: str
    authors: list[str] = field(default_factory=list)
    narrators: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class Review:
    review_id: str
    asin: str
    book_title: str
    body: str
    author: str | None = None
    rating: int | None = None
    title: str | None = None
    reviewer: str | None = None
    created_at: str | None = None  # ISO-8601 if known
    source: str = "audible"

    def to_dict(self) -> dict:
        return {
            "review_id": self.review_id,
            "asin": self.asin,
            "book_title": self.book_title,
            "author": self.author,
            "rating": self.rating,
            "title": self.title,
            "body": self.body,
            "reviewer": self.reviewer,
            "created_at": self.created_at,
            "source": self.source,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "Review":
        return cls(
            review_id=data["review_id"],
            asin=data["asin"],
            book_title=data.get("book_title", ""),
            body=data.get("body", ""),
            author=data.get("author"),
            rating=data.get("rating"),
            title=data.get("title"),
            reviewer=data.get("reviewer"),
            created_at=data.get("created_at"),
            source=data.get("source", "audible"),
        )
