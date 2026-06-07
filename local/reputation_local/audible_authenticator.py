"""AudibleAuthenticator — turn credentials into an authenticated session.

Wraps ``audible.Authenticator``. On first login it performs the full login
(which may prompt for CAPTCHA / OTP / CVF via the library's default callbacks)
and caches the session to ``auth.json``. Later runs restore from that file.

The ``audible`` import is done lazily so the rest of the package can be imported
and tested without the dependency installed.
"""

from __future__ import annotations

import os

from .config_models import AudibleCredentials


class AudibleAuthenticator:
    def __init__(self, credentials: AudibleCredentials, auth_cache_path: str) -> None:
        self._credentials = credentials
        self._auth_cache_path = auth_cache_path

    def authenticate(self):
        """Return an authenticated ``audible.Authenticator``."""
        import audible  # lazy import — see module docstring

        if os.path.exists(self._auth_cache_path):
            return audible.Authenticator.from_file(self._auth_cache_path)

        auth = audible.Authenticator.from_login(
            self._credentials.username,
            self._credentials.password,
            locale=self._credentials.marketplace,
        )
        auth.to_file(self._auth_cache_path)
        return auth
