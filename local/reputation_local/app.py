"""App — orchestrator.

Wires the small classes together and sequences the operations the CLI asks for.
Contains no business logic of its own beyond sequencing.
"""

from __future__ import annotations

from .book_searcher import BookSearcher
from .models import Book, Review
from .review_poster import ReviewPoster
from .review_reader import ReviewReader
from .review_uploader import ReviewUploader, UploadResult


class App:
    def __init__(
        self,
        searcher: BookSearcher,
        reader: ReviewReader,
        poster: ReviewPoster,
        uploader: ReviewUploader,
    ) -> None:
        self._searcher = searcher
        self._reader = reader
        self._poster = poster
        self._uploader = uploader

    def search(self, query: str) -> list[Book]:
        return self._searcher.search(query)

    def read_reviews(self, asin: str) -> list[Review]:
        return self._reader.read(asin)

    def post_review(self, asin: str, rating: int, title: str, body: str) -> Review:
        return self._poster.post(asin, rating, title, body)

    def share(self) -> UploadResult:
        return self._uploader.upload_all()
