"""AudibleGateway — the ONLY class that knows Audible's API shape.

A thin wrapper over ``audible.Client``. It exposes just the raw calls the app
needs and returns the raw response dicts; converting to Book/Review objects
happens in the searcher/reader so this class stays dumb.

NOTE: Audible has no official public API. These endpoint paths and response
groups are best-effort against the unofficial ``mkb79/Audible`` client and may
need adjustment. Keeping them here means any repair is a one-file change.
"""

from __future__ import annotations


class AudibleGateway:
    # Response groups requested for catalog calls. Adjust here if Audible changes.
    _SEARCH_GROUPS = "product_desc,product_attrs,contributors"
    _REVIEW_GROUPS = "product_desc,product_attrs,reviews,rating"

    def __init__(self, auth) -> None:
        import audible  # lazy import so the package imports without the dependency

        self._client = audible.Client(auth=auth)

    def search_products(self, query: str, num_results: int = 20) -> dict:
        """Search the catalog by keywords. Returns the raw response dict."""
        return self._client.get(
            "1.0/catalog/products",
            keywords=query,
            num_results=num_results,
            response_groups=self._SEARCH_GROUPS,
        )

    def get_product_reviews(self, asin: str) -> dict:
        """Fetch a single product (with its reviews). Returns the raw dict."""
        return self._client.get(
            f"1.0/catalog/products/{asin}",
            response_groups=self._REVIEW_GROUPS,
        )

    def post_review(self, asin: str, payload: dict) -> dict:
        """Submit a review for a product.

        WARNING: the review-submission endpoint is NOT verified against the
        unofficial API — Audible/Amazon review posting normally goes through the
        website, and ``mkb79/Audible`` does not document a review endpoint. The
        path and payload below are a placeholder and almost certainly need to be
        confirmed before this works. Kept here so all Audible knowledge stays in
        one class.
        """
        raise NotImplementedError(
            "Posting reviews to Audible is not yet wired up: the unofficial API "
            "has no confirmed review-submission endpoint. See AudibleGateway."
        )
