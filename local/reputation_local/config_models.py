"""Dumb configuration value objects.

These hold settings only. They perform no I/O and contain no logic beyond
trivial derivations. `ConfigLoader` (config_loader.py) is what builds them.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class AudibleCredentials:
    """Audible/Amazon login fields."""

    username: str
    password: str
    marketplace: str  # locale / country code, e.g. "us", "uk", "de"


@dataclass(frozen=True)
class WebserverTarget:
    """Where the central webserver lives."""

    url: str   # scheme + host, e.g. "http://reviews.example.com"
    port: int

    @property
    def base_url(self) -> str:
        """Full base URL, e.g. "http://reviews.example.com:8000"."""
        return f"{self.url.rstrip('/')}:{self.port}"


@dataclass(frozen=True)
class AppConfig:
    """Immutable holder for all local-program settings."""

    audible: AudibleCredentials
    webserver: WebserverTarget
    reviews_path: str
    auth_cache_path: str
