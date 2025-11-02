#!/usr/bin/env python3
"""Validate the structure of an SSM Automation document."""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple


def _load_yaml(path: Path) -> Dict[str, Any]:
    try:
        import yaml  # type: ignore
    except ModuleNotFoundError:
        return _fallback_load_yaml(path)

    try:
        with path.open("r", encoding="utf-8") as handle:
            return yaml.safe_load(handle)
    except yaml.YAMLError as exc:  # type: ignore[attr-defined]
        raise SystemExit(f"YAML syntax error in {path}: {exc}") from exc


@dataclass
class _Line:
    raw: str
    indent: int
    content: str
    number: int
    is_blank: bool
    is_comment: bool


def _fallback_load_yaml(path: Path) -> Dict[str, Any]:
    """Parse YAML with a minimal indentation-based reader.

    CloudShell images do not ship with PyYAML and outbound internet access may
    be restricted, which prevents installing it with ``pip``. To keep the
    validator usable in that environment, this function implements a tiny YAML
    subset parser that understands the constructs used in our Automation
    documents (mappings, sequences, quoted scalars, and block scalars). It is
    *not* a general-purpose replacement for PyYAML, but it is sufficient for the
    repository's documents.
    """

    lines = _preprocess_lines(path.read_text(encoding="utf-8"))
    document, index = _parse_block(lines, 0, 0)
    while index < len(lines) and lines[index].is_blank:
        index += 1
    if index != len(lines):
        raise SystemExit(
            f"YAML syntax error in {path}: unexpected content after line {lines[index].number}."
        )
    if not isinstance(document, dict):
        raise SystemExit("Document root must be a mapping/object.")
    return document


def _preprocess_lines(text: str) -> List[_Line]:
    result: List[_Line] = []
    for number, raw in enumerate(text.splitlines(), start=1):
        if raw.strip() in {"---", "..."}:
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        stripped = raw[indent:]
        is_blank = stripped.strip() == ""
        is_comment = stripped.lstrip().startswith("#")
        result.append(
            _Line(
                raw=raw,
                indent=indent,
                content=stripped,
                number=number,
                is_blank=is_blank,
                is_comment=is_comment,
            )
        )
    return result


def _parse_block(lines: List[_Line], index: int, indent: int) -> Tuple[Any, int]:
    container: Any | None = None

    while index < len(lines):
        index = _skip_ignorable(lines, index)
        if index >= len(lines):
            break
        line = lines[index]
        if line.indent < indent:
            break
        if line.indent > indent:
            raise SystemExit(
                f"Invalid indentation on line {line.number}: expected {indent} spaces, found {line.indent}."
            )

        text = line.content
        if text.startswith("- ") or text == "-":
            if container is None:
                container = []
            elif not isinstance(container, list):
                raise SystemExit(
                    f"Mixing sequence and mapping entries near line {line.number}."
                )
            value_text = text[1:].lstrip()
            index += 1
            value, index = _parse_list_value(lines, index, indent, value_text, line.number)
            container.append(value)
        else:
            key, sep, remainder = text.partition(":")
            if not sep:
                raise SystemExit(
                    f"Expected ':' separating key/value on line {line.number}."
                )
            key = key.strip()
            if not key:
                raise SystemExit(f"Empty mapping key on line {line.number}.")
            if container is None:
                container = {}
            elif not isinstance(container, dict):
                raise SystemExit(
                    f"Mixing sequence and mapping entries near line {line.number}."
                )
            value_text = remainder.lstrip()
            index += 1
            value, index = _parse_mapping_value(
                lines, index, indent, value_text, line.number
            )
            container[key] = value

    if container is None:
        return {}, index
    return container, index


def _parse_list_value(
    lines: List[_Line],
    index: int,
    parent_indent: int,
    value_text: str,
    line_number: int,
) -> Tuple[Any, int]:
    if not value_text:
        return _parse_block(lines, index, parent_indent + 2)

    if ":" in value_text:
        key, _, remainder = value_text.partition(":")
        nested: Dict[str, Any] = {
            key.strip(): _parse_scalar(remainder.lstrip(), line_number)
        }
        next_index = _skip_ignorable(lines, index)
        if next_index < len(lines) and lines[next_index].indent >= parent_indent + 2:
            extra, next_index = _parse_block(lines, next_index, parent_indent + 2)
            if not isinstance(extra, dict):
                raise SystemExit(
                    f"List item on line {line_number} expects mapping content."
                )
            nested.update(extra)
        return nested, next_index

    if value_text in {"|", "|-", "|+", ">", ">-", ">+"}:
        return _collect_block_scalar(
            lines, index, parent_indent + 2, value_text, line_number
        )

    return _parse_scalar(value_text, line_number), index


def _parse_mapping_value(
    lines: List[_Line],
    index: int,
    parent_indent: int,
    value_text: str,
    line_number: int,
) -> Tuple[Any, int]:
    if not value_text:
        return _parse_block(lines, index, parent_indent + 2)

    if value_text in {"|", "|-", "|+", ">", ">-", ">+"}:
        return _collect_block_scalar(
            lines, index, parent_indent + 2, value_text, line_number
        )

    return _parse_scalar(value_text, line_number), index


def _collect_block_scalar(
    lines: List[_Line],
    index: int,
    indent: int,
    style: str,
    line_number: int,
) -> Tuple[str, int]:
    collected: List[str] = []
    started = False

    while index < len(lines):
        line = lines[index]
        if line.is_comment:
            index += 1
            continue
        if line.is_blank and not started:
            break
        if line.indent < indent and not line.is_blank:
            break
        started = True
        if line.is_blank:
            collected.append("")
        else:
            segment = line.raw[indent:]
            collected.append(segment)
        index += 1

    text = _render_block(collected, style)
    return text, index


def _render_block(lines: List[str], style: str) -> str:
    if not lines:
        return ""
    if style.startswith("|"):
        text = "\n".join(lines)
    else:
        paragraphs: List[str] = []
        current: List[str] = []
        for line in lines:
            if line.strip() == "":
                if current:
                    paragraphs.append(" ".join(current))
                    current = []
                paragraphs.append("")
            else:
                current.append(line.strip())
        if current:
            paragraphs.append(" ".join(current))
        text = "\n".join(paragraphs)
    if style.endswith("-"):
        text = text.rstrip("\n")
    return text


def _parse_scalar(value: str, line_number: int) -> Any:
    if value == "":
        return ""
    if value.startswith("\"") and value.endswith("\"") and len(value) >= 2:
        return bytes(value[1:-1], "utf-8").decode("unicode_escape")
    if value.startswith("'") and value.endswith("'") and len(value) >= 2:
        return value[1:-1].replace("''", "'")
    if value in {"true", "True"}:
        return True
    if value in {"false", "False"}:
        return False
    if value in {"null", "Null", "~"}:
        return None
    if value.isdigit():
        try:
            return int(value)
        except ValueError as exc:  # pragma: no cover - defensive
            raise SystemExit(
                f"Invalid integer literal '{value}' on line {line_number}."
            ) from exc
    return value


def _skip_ignorable(lines: List[_Line], index: int) -> int:
    while index < len(lines) and (lines[index].is_blank or lines[index].is_comment):
        index += 1
    return index


def _validate_document(document: Any) -> List[str]:
    errors: List[str] = []

    if not isinstance(document, dict):
        return ["Document root must be a mapping/object."]

    required_top_level = ("schemaVersion", "mainSteps")
    for key in required_top_level:
        if key not in document:
            errors.append(f"Missing required top-level key: '{key}'.")

    schema_version = document.get("schemaVersion")
    if schema_version is not None and not isinstance(schema_version, str):
        errors.append("'schemaVersion' must be a string.")

    parameters = document.get("parameters")
    if parameters is not None and not isinstance(parameters, dict):
        errors.append("'parameters' must be a mapping if present.")

    main_steps = document.get("mainSteps")
    if not isinstance(main_steps, list) or not main_steps:
        errors.append("'mainSteps' must be a non-empty list.")
    else:
        required_step_keys = ("name", "action", "inputs")
        for index, step in enumerate(main_steps):
            if not isinstance(step, dict):
                errors.append(f"mainSteps[{index}] must be a mapping.")
                continue
            for key in required_step_keys:
                if key not in step:
                    errors.append(f"mainSteps[{index}] is missing '{key}'.")

    outputs = document.get("outputs")
    if outputs is not None:
        if not isinstance(outputs, list):
            errors.append("'outputs' must be a list when provided.")
        else:
            required_output_keys = ("Name", "Selector", "Type")
            for index, output in enumerate(outputs):
                if not isinstance(output, dict):
                    errors.append(f"outputs[{index}] must be a mapping.")
                    continue
                for key in required_output_keys:
                    if key not in output:
                        errors.append(
                            f"outputs[{index}] is missing '{key}'."
                        )

    return errors


def _parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run a minimal structural validation against an SSM Automation"
            " document before uploading it with aws ssm create-document."
        )
    )
    parser.add_argument(
        "path",
        type=Path,
        help="Path to the Automation document (YAML).",
    )
    return parser.parse_args(argv)


def main(argv: Iterable[str] | None = None) -> int:
    args = _parse_args(argv)
    document = _load_yaml(args.path)
    errors = _validate_document(document)

    if errors:
        sys.stderr.write(
            f"{len(errors)} problem(s) found in {args.path}:\n"
        )
        for item in errors:
            sys.stderr.write(f"  - {item}\n")
        return 1

    print(f"{args.path} passed structural validation.")
    return 0


if __name__ == "__main__":  # pragma: no cover - CLI entry
    raise SystemExit(main())
