from __future__ import annotations

import json
import os
from typing import Any


class ClaudeStatsLlmConfig:
    def __init__(
        self,
        model: str | None = None,
        temperature: float | None = 0.1,
        api_key: str | None = None,
        max_tokens: int | None = 2000,
        top_p: float | None = 0.1,
        top_k: int = 1,
        enable_vision: bool = False,
        vision_details: str | None = "auto",
        reasoning_effort: str | None = None,
        openai_base_url: str | None = None,
        anthropic_base_url: str | None = None,
        **_: Any,
    ):
        self.model = model
        self.temperature = temperature
        self.api_key = api_key
        self.max_tokens = max_tokens
        self.top_p = top_p
        self.top_k = top_k
        self.enable_vision = enable_vision
        self.vision_details = vision_details
        self.reasoning_effort = reasoning_effort
        self.openai_base_url = openai_base_url
        self.anthropic_base_url = anthropic_base_url


def register_mem0_llm_providers() -> None:
    from mem0.utils.factory import LlmFactory  # type: ignore

    LlmFactory.register_provider(
        "claude_stats_openai_responses",
        "memoryd.llm_providers.OpenAIResponsesLLM",
        ClaudeStatsLlmConfig,
    )
    LlmFactory.register_provider(
        "claude_stats_anthropic_messages",
        "memoryd.llm_providers.AnthropicMessagesLLM",
        ClaudeStatsLlmConfig,
    )


class OpenAIResponsesLLM:
    def __init__(self, config: ClaudeStatsLlmConfig | dict[str, Any] | None = None):
        from openai import OpenAI  # type: ignore

        self.config = _coerce_config(config)
        if not self.config.model:
            self.config.model = "gpt-5-mini"
        self.client = OpenAI(
            api_key=self.config.api_key or os.getenv("OPENAI_API_KEY"),
            base_url=self.config.openai_base_url or os.getenv("OPENAI_BASE_URL") or "https://api.openai.com/v1",
        )

    def generate_response(
        self,
        messages: list[dict[str, Any]],
        response_format: Any = None,
        tools: list[dict[str, Any]] | None = None,
        tool_choice: str = "auto",
        **_: Any,
    ) -> str | dict[str, Any]:
        params: dict[str, Any] = {
            "model": self.config.model,
            "input": messages,
        }
        if self.config.max_tokens:
            params["max_output_tokens"] = self.config.max_tokens
        if self.config.temperature is not None and not _is_reasoning_model(str(self.config.model or "")):
            params["temperature"] = self.config.temperature
        if self.config.reasoning_effort:
            params["reasoning"] = {"effort": self.config.reasoning_effort}
        if response_format:
            text_format = _responses_text_format(response_format)
            if text_format:
                params["text"] = {"format": text_format}
        if tools:
            params["tools"] = _responses_tools(tools)
            params["tool_choice"] = tool_choice

        response = self.client.responses.create(**params)
        return _parse_responses_output(response, tools)


class AnthropicMessagesLLM:
    def __init__(self, config: ClaudeStatsLlmConfig | dict[str, Any] | None = None):
        try:
            import anthropic  # type: ignore
        except ImportError as error:
            raise ImportError("The 'anthropic' library is required for Anthropic memory extraction.") from error

        self.config = _coerce_config(config)
        if not self.config.model:
            self.config.model = "claude-haiku-4-5-latest"
        kwargs: dict[str, Any] = {"api_key": self.config.api_key or os.getenv("ANTHROPIC_API_KEY")}
        base_url = self.config.anthropic_base_url or os.getenv("ANTHROPIC_BASE_URL")
        if base_url:
            kwargs["base_url"] = base_url
        self.client = anthropic.Anthropic(**kwargs)

    def generate_response(
        self,
        messages: list[dict[str, Any]],
        response_format: Any = None,
        tools: list[dict[str, Any]] | None = None,
        tool_choice: str = "auto",
        **_: Any,
    ) -> str | dict[str, Any]:
        system_message = ""
        filtered_messages: list[dict[str, Any]] = []
        for message in messages:
            if message.get("role") == "system":
                system_message = str(message.get("content") or "")
            else:
                filtered_messages.append(message)

        params: dict[str, Any] = {
            "model": self.config.model,
            "messages": filtered_messages,
            "max_tokens": self.config.max_tokens or 2000,
        }
        if system_message:
            params["system"] = system_message
        if self.config.temperature is not None:
            params["temperature"] = self.config.temperature
        if tools:
            params["tools"] = _anthropic_tools(tools)
            params["tool_choice"] = {"type": "auto"} if tool_choice == "auto" else tool_choice

        response = self.client.messages.create(**params)
        return _parse_anthropic_output(response, tools)


def _coerce_config(config: ClaudeStatsLlmConfig | dict[str, Any] | None) -> ClaudeStatsLlmConfig:
    if config is None:
        return ClaudeStatsLlmConfig()
    if isinstance(config, dict):
        return ClaudeStatsLlmConfig(**config)
    return config


def _responses_text_format(response_format: Any) -> dict[str, Any] | None:
    if isinstance(response_format, dict):
        kind = response_format.get("type")
        if kind in {"json_object", "json_schema", "text"}:
            return response_format
    return None


def _responses_tools(tools: list[dict[str, Any]]) -> list[dict[str, Any]]:
    converted: list[dict[str, Any]] = []
    for tool in tools:
        if tool.get("type") != "function":
            converted.append(tool)
            continue
        function = tool.get("function") if isinstance(tool.get("function"), dict) else {}
        converted.append(
            {
                "type": "function",
                "name": function.get("name") or tool.get("name"),
                "description": function.get("description") or "",
                "parameters": function.get("parameters") or {},
            }
        )
    return converted


def _anthropic_tools(tools: list[dict[str, Any]]) -> list[dict[str, Any]]:
    converted: list[dict[str, Any]] = []
    for tool in tools:
        function = tool.get("function") if isinstance(tool.get("function"), dict) else tool
        converted.append(
            {
                "name": function.get("name") or tool.get("name"),
                "description": function.get("description") or "",
                "input_schema": function.get("parameters") or function.get("input_schema") or {},
            }
        )
    return converted


def _parse_responses_output(response: Any, tools: list[dict[str, Any]] | None) -> str | dict[str, Any]:
    text = str(_attr(response, "output_text") or "")
    tool_calls: list[dict[str, Any]] = []
    for item in _attr(response, "output") or []:
        item_type = _attr(item, "type")
        if item_type == "message":
            for content in _attr(item, "content") or []:
                if _attr(content, "type") in {"output_text", "text"}:
                    text += str(_attr(content, "text") or "")
        elif item_type == "function_call":
            arguments = _json_object(_attr(item, "arguments"))
            tool_calls.append({"name": _attr(item, "name") or "", "arguments": arguments})
    if tools:
        return {"content": text, "tool_calls": tool_calls}
    return text


def _parse_anthropic_output(response: Any, tools: list[dict[str, Any]] | None) -> str | dict[str, Any]:
    text_parts: list[str] = []
    tool_calls: list[dict[str, Any]] = []
    for block in getattr(response, "content", []) or []:
        block_type = _attr(block, "type")
        if block_type == "text":
            text_parts.append(str(_attr(block, "text") or ""))
        elif block_type == "tool_use":
            tool_calls.append({"name": _attr(block, "name") or "", "arguments": _attr(block, "input") or {}})
    content = "".join(text_parts)
    if tools:
        return {"content": content, "tool_calls": tool_calls}
    return content


def _json_object(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    if not isinstance(value, str) or not value:
        return {}
    try:
        parsed = json.loads(value)
        return parsed if isinstance(parsed, dict) else {}
    except json.JSONDecodeError:
        return {}


def _attr(value: Any, name: str) -> Any:
    if isinstance(value, dict):
        return value.get(name)
    return getattr(value, name, None)


def _is_reasoning_model(model: str) -> bool:
    base_model = model.lower().rsplit("/", 1)[-1]
    return base_model in {"o1", "o1-preview", "o3", "o3-mini", "gpt-5", "gpt-5-mini"} or base_model.startswith(("o1-", "o3-"))
