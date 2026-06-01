from __future__ import annotations

import hashlib
import html
import re
import socket
import time
from typing import Any
from urllib.parse import urlparse

from .config import LocalAIConfig


def safe_group_id(value: str | None) -> str:
    raw = value or "default"
    safe = "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in raw)
    digest = hashlib.sha256(raw.encode("utf-8")).hexdigest()[:12]
    return f"p_{safe[:48]}_{digest}"


def protocol_label(protocol: str) -> str:
    return {
        "openai_chat_completions": "OpenAI Chat",
        "openai_responses": "OpenAI Responses",
        "anthropic_messages": "Anthropic Messages",
    }.get(protocol, protocol or "unknown")


def endpoint_error(config: LocalAIConfig) -> str:
    llm_error = endpoint_url_error(config.llm.base_url, label="LLM")
    if llm_error:
        return llm_error
    embedding_error = endpoint_url_error(config.embedding.base_url, label="embedding")
    if embedding_error:
        return embedding_error
    return ""


def endpoint_url_error(base_url: str, *, label: str) -> str:
    parsed = urlparse(base_url)
    host = parsed.hostname
    if not host:
        return f"{label} base URL is not configured"
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    try:
        with socket.create_connection((host, port), timeout=0.25):
            return ""
    except OSError as error:
        detail = error.strerror or str(error)
        if host in {"127.0.0.1", "localhost", "::1"} and port == 18765:
            return f"{label} local AI helper stopped or unreachable at {host}:{port} ({detail})"
        return f"{label} endpoint {host}:{port} is unreachable ({detail})"


def compact_error(error: Exception) -> str:
    text = html.unescape(str(error))
    text = re.sub(r"(?is)<script.*?</script>|<style.*?</style>", " ", text)
    text = re.sub(r"(?is)<[^>]+>", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) > 320:
        text = text[:317].rstrip() + "..."
    return text or error.__class__.__name__


def float_value(value: Any, default: float) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def timestamp(value: Any) -> float:
    from datetime import datetime

    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str) and value:
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
        except ValueError:
            return time.time()
    return time.time()


def timestamp_or_none(value: Any) -> float | None:
    if value is None or value == "":
        return None
    try:
        return timestamp(value)
    except Exception:  # noqa: BLE001
        return None
