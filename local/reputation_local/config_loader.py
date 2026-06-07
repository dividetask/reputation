"""ConfigLoader — read and validate config.yaml, produce an AppConfig.

This is the only class that reads the YAML file. Everything else receives typed
value objects (see config_models.py).
"""

from __future__ import annotations

import yaml

from .config_models import AppConfig, AudibleCredentials, WebserverTarget


class ConfigError(Exception):
    """Raised when the config file is missing required fields or malformed."""


class ConfigLoader:
    def __init__(self, path: str) -> None:
        self._path = path

    def load(self) -> AppConfig:
        """Read the YAML file, validate it, and build an AppConfig."""
        try:
            with open(self._path, "r", encoding="utf-8") as handle:
                raw = yaml.safe_load(handle) or {}
        except FileNotFoundError as exc:
            raise ConfigError(f"Config file not found: {self._path}") from exc
        except yaml.YAMLError as exc:
            raise ConfigError(f"Config file is not valid YAML: {exc}") from exc

        audible = self._build_credentials(self._section(raw, "audible"))
        webserver = self._build_target(self._section(raw, "webserver"))
        storage = raw.get("storage") or {}

        return AppConfig(
            audible=audible,
            webserver=webserver,
            reviews_path=storage.get("reviews_path", "reviews.json"),
            auth_cache_path=storage.get("auth_cache_path", "auth.json"),
        )

    @staticmethod
    def _section(raw: dict, name: str) -> dict:
        section = raw.get(name)
        if not isinstance(section, dict):
            raise ConfigError(f"Config is missing required '{name}' section.")
        return section

    @staticmethod
    def _build_credentials(section: dict) -> AudibleCredentials:
        for field in ("username", "password", "marketplace"):
            if not section.get(field):
                raise ConfigError(f"Config 'audible.{field}' is required.")
        return AudibleCredentials(
            username=section["username"],
            password=section["password"],
            marketplace=section["marketplace"],
        )

    @staticmethod
    def _build_target(section: dict) -> WebserverTarget:
        if not section.get("url"):
            raise ConfigError("Config 'webserver.url' is required.")
        if not section.get("port"):
            raise ConfigError("Config 'webserver.port' is required.")
        return WebserverTarget(url=section["url"], port=int(section["port"]))
