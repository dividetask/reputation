"""CLI — render menus/prompts and collect user input.

No business logic: it only calls into App and prints results.
"""

from __future__ import annotations

from .app import App

_MENU = """
Reputation — local program
  1) Search for a book
  2) Read reviews for a book (ASIN)
  3) Post a review
  4) Share collected reviews with the webserver
  q) Quit
"""


class CLI:
    def __init__(self, app: App) -> None:
        self._app = app

    def run(self) -> None:
        while True:
            print(_MENU)
            choice = input("> ").strip().lower()
            if choice == "1":
                self._search()
            elif choice == "2":
                self._read()
            elif choice == "3":
                self._post()
            elif choice == "4":
                self._share()
            elif choice == "q":
                return
            else:
                print("Unknown option.")

    def _search(self) -> None:
        query = input("Search keywords: ").strip()
        books = self._app.search(query)
        if not books:
            print("No results.")
            return
        for book in books:
            print(f"  {book.asin}  {book.title} — {', '.join(book.authors)}")

    def _read(self) -> None:
        asin = input("ASIN: ").strip()
        reviews = self._app.read_reviews(asin)
        print(f"Read and saved {len(reviews)} review(s).")
        for review in reviews:
            rating = review.rating if review.rating is not None else "-"
            print(f"  [{rating}] {review.title or ''}: {review.body[:80]}")

    def _post(self) -> None:
        asin = input("ASIN: ").strip()
        rating = int(input("Rating (1-5): ").strip())
        title = input("Title: ").strip()
        body = input("Review: ").strip()
        try:
            self._app.post_review(asin, rating, title, body)
            print("Posted.")
        except NotImplementedError as exc:
            print(f"Could not post: {exc}")

    def _share(self) -> None:
        try:
            result = self._app.share()
            print(
                f"Uploaded. received={result.received} "
                f"added={result.added} duplicates={result.duplicates}"
            )
        except Exception as exc:  # noqa: BLE001 — surface any upload failure to the user
            print(f"Upload failed: {exc}")
