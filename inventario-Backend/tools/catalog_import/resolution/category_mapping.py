#!/usr/bin/env python3
"""Build an auditable A2.1 Cronos category-mapping proposal from A2.0 rows."""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
import tempfile
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence


CATALOG_IMPORT_DIR = Path(__file__).resolve().parents[1]
if str(CATALOG_IMPORT_DIR) not in sys.path:
    sys.path.insert(0, str(CATALOG_IMPORT_DIR))

import catalog_tool  # noqa: E402
from resolution import candidate_resolution  # noqa: E402


CATEGORY_MAPPING_HEADERS = [
    "barcode",
    "off_main_category",
    "off_categories_tags",
    "cronos_category_candidate",
    "mapping_status",
    "mapping_rule_ids",
    "matched_off_tags",
    "mapping_reason",
    "ruleset_version",
    "ruleset_sha256",
    "resolution_record_sha256",
    "category_mapping_record_sha256",
]

RULE_ACTIONS = {"map", "review", "exclude"}
MAPPING_STATUSES = {"mapped", "unresolved", "review", "excluded"}
MAPPING_REASONS = {
    "exact_main_category_rule",
    "exact_curated_tag_rule",
    "no_category_evidence",
    "no_matching_rule",
    "review_required",
    "ambiguous_target",
    "out_of_scope_for_initial_catalog",
}
REASONS_BY_STATUS = {
    "mapped": {"exact_main_category_rule", "exact_curated_tag_rule"},
    "unresolved": {"no_category_evidence", "no_matching_rule"},
    "review": {"review_required", "ambiguous_target"},
    "excluded": {"out_of_scope_for_initial_catalog"},
}
RULE_REQUIRED_FIELDS = {
    "rule_id",
    "action",
    "target_category",
    "reason",
}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
RULE_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
OFF_TAG_RE = re.compile(r"^[a-z]{2,3}:[^\s,|]+$")
CSV_FIELD_SIZE_LIMIT = 64 * 1024 * 1024
DEFAULT_RULES_PATH = Path(__file__).with_name("category_mapping_rules.json")


class CategoryMappingToolError(Exception):
    """Usage, I/O, or malformed configuration error (exit code 2)."""


class CategoryMappingValidationError(Exception):
    """Invalid input or generated mapping content (exit code 1)."""


@dataclass(frozen=True)
class CategoryRule:
    rule_id: str
    action: str
    match_main_category_any: tuple[str, ...]
    match_tags_any: tuple[str, ...]
    target_category: str | None
    reason: str

    def logical_record(self) -> dict[str, Any]:
        return {
            "rule_id": self.rule_id,
            "action": self.action,
            "match_main_category_any": list(self.match_main_category_any),
            "match_tags_any": list(self.match_tags_any),
            "target_category": self.target_category,
            "reason": self.reason,
        }


@dataclass(frozen=True)
class CategoryRuleset:
    ruleset_version: str
    rules: tuple[CategoryRule, ...]
    ruleset_sha256: str


def _path(value: str) -> Path:
    return Path(value).expanduser().resolve()


def _nfc_trim(value: Any) -> str:
    text = "" if value is None else str(value)
    return unicodedata.normalize("NFC", text).strip()


def _normalize_tag(value: Any) -> str:
    return _nfc_trim(value).casefold()


def _load_categories(vocabularies_path: Path = catalog_tool.DEFAULT_CONFIG) -> list[str]:
    try:
        vocabularies = catalog_tool._load_vocabularies(vocabularies_path)  # noqa: SLF001
    except catalog_tool.CatalogToolError as error:
        raise CategoryMappingToolError(str(error)) from error
    categories = vocabularies["categories"]
    if not categories or len(categories) != len(set(categories)):
        raise CategoryMappingToolError("P1.2 categories must be non-empty and unique")
    return list(categories)


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise CategoryMappingToolError(f"Cannot read category rules {path}: {error}") from error


def _validate_matcher(
    raw_rule: dict[str, Any], matcher_name: str, rule_id: str
) -> tuple[str, ...]:
    raw_tags = raw_rule.get(matcher_name, [])
    if not isinstance(raw_tags, list):
        raise CategoryMappingToolError(
            f"Rule {rule_id} {matcher_name} must be a string array"
        )
    normalized_tags: list[str] = []
    for raw_tag in raw_tags:
        if not isinstance(raw_tag, str):
            raise CategoryMappingToolError(
                f"Rule {rule_id} {matcher_name} contains a non-string tag"
            )
        normalized = _normalize_tag(raw_tag)
        if raw_tag != normalized or not OFF_TAG_RE.fullmatch(normalized):
            raise CategoryMappingToolError(
                f"Rule {rule_id} {matcher_name} tag must be an exact normalized OFF tag: "
                f"{raw_tag!r}"
            )
        normalized_tags.append(normalized)
    if len(normalized_tags) != len(set(normalized_tags)):
        raise CategoryMappingToolError(
            f"Rule {rule_id} {matcher_name} contains duplicate tags"
        )
    return tuple(sorted(normalized_tags))


def load_ruleset(path: Path, categories: Sequence[str]) -> CategoryRuleset:
    raw = _read_json(path)
    if not isinstance(raw, dict):
        raise CategoryMappingToolError("Category ruleset must contain a JSON object")

    version = raw.get("ruleset_version")
    if not isinstance(version, str) or not _nfc_trim(version):
        raise CategoryMappingToolError("ruleset_version is required and must be a string")
    if version != _nfc_trim(version):
        raise CategoryMappingToolError("ruleset_version must not contain exterior whitespace")
    raw_rules = raw.get("rules")
    if not isinstance(raw_rules, list):
        raise CategoryMappingToolError("rules must be a JSON array")

    allowed_categories = set(categories)
    rules: list[CategoryRule] = []
    seen_rule_ids: set[str] = set()
    for index, raw_rule in enumerate(raw_rules, start=1):
        location = f"rule {index}"
        if not isinstance(raw_rule, dict):
            raise CategoryMappingToolError(f"{location} must be a JSON object")
        missing = sorted(RULE_REQUIRED_FIELDS.difference(raw_rule))
        if missing:
            raise CategoryMappingToolError(
                f"{location} is missing required fields: {', '.join(missing)}"
            )

        rule_id = raw_rule["rule_id"]
        if not isinstance(rule_id, str) or not RULE_ID_RE.fullmatch(rule_id):
            raise CategoryMappingToolError(f"{location} has an invalid rule_id")
        if rule_id in seen_rule_ids:
            raise CategoryMappingToolError(f"Duplicate rule_id: {rule_id}")
        seen_rule_ids.add(rule_id)

        action = raw_rule["action"]
        if action not in RULE_ACTIONS:
            raise CategoryMappingToolError(f"Rule {rule_id} has an invalid action")

        main_category_tags = _validate_matcher(
            raw_rule, "match_main_category_any", rule_id
        )
        general_tags = _validate_matcher(raw_rule, "match_tags_any", rule_id)
        if not main_category_tags and not general_tags:
            raise CategoryMappingToolError(
                f"Rule {rule_id} requires at least one non-empty matcher"
            )

        target = raw_rule["target_category"]
        if action == "map":
            if not isinstance(target, str) or not target:
                raise CategoryMappingToolError(f"Map rule {rule_id} requires target_category")
            if target not in allowed_categories:
                raise CategoryMappingToolError(
                    f"Rule {rule_id} target_category is outside the P1.2 vocabulary: {target!r}"
                )
        elif target is not None:
            raise CategoryMappingToolError(
                f"{action.capitalize()} rule {rule_id} requires target_category = null"
            )

        reason = raw_rule["reason"]
        if not isinstance(reason, str) or not _nfc_trim(reason):
            raise CategoryMappingToolError(f"Rule {rule_id} requires a non-empty reason")
        reason = _nfc_trim(reason)
        rules.append(
            CategoryRule(
                rule_id=rule_id,
                action=action,
                match_main_category_any=main_category_tags,
                match_tags_any=general_tags,
                target_category=target,
                reason=reason,
            )
        )

    rules.sort(key=lambda rule: rule.rule_id)
    logical_ruleset = {
        "ruleset_version": version,
        "rules": [rule.logical_record() for rule in rules],
    }
    return CategoryRuleset(
        ruleset_version=version,
        rules=tuple(rules),
        ruleset_sha256=catalog_tool.record_hash(logical_ruleset),
    )


def _load_resolution(path: Path) -> list[dict[str, str]]:
    csv.field_size_limit(CSV_FIELD_SIZE_LIMIT)
    try:
        handle = path.open("r", encoding="utf-8-sig", newline="")
    except OSError as error:
        raise CategoryMappingToolError(f"Cannot read A2.0 resolution {path}: {error}") from error

    rows: list[dict[str, str]] = []
    seen_barcodes: set[str] = set()
    try:
        with handle:
            reader = csv.reader(handle, strict=True)
            try:
                headers = next(reader)
            except StopIteration as error:
                raise CategoryMappingValidationError(
                    "A2.0 resolution is empty and has no header"
                ) from error
            if headers != candidate_resolution.RESOLUTION_HEADERS:
                raise CategoryMappingValidationError("A2.0 resolution header is invalid")
            for row_number, raw_row in enumerate(reader, start=2):
                if len(raw_row) != len(headers):
                    raise CategoryMappingValidationError(
                        f"A2.0 resolution row {row_number} has an invalid field count"
                    )
                row = dict(zip(headers, raw_row, strict=True))
                barcode = row["barcode"]
                if not barcode:
                    raise CategoryMappingValidationError(
                        f"A2.0 resolution row {row_number} has an empty barcode"
                    )
                if barcode in seen_barcodes:
                    raise CategoryMappingValidationError(f"Duplicate resolution barcode: {barcode}")
                seen_barcodes.add(barcode)
                if row["source_match_status"] != "matched":
                    raise CategoryMappingValidationError(
                        f"A2.0 resolution row {row_number} is not matched"
                    )
                if row["category_status"] not in candidate_resolution.STATUS_VALUES:
                    raise CategoryMappingValidationError(
                        f"A2.0 resolution row {row_number} has invalid category_status"
                    )
                resolution_hash = row["resolution_record_sha256"]
                if not SHA256_RE.fullmatch(resolution_hash):
                    raise CategoryMappingValidationError(
                        f"A2.0 resolution row {row_number} has invalid resolution_record_sha256"
                    )
                expected_hash = catalog_tool.record_hash(
                    {
                        header: row[header]
                        for header in candidate_resolution.RESOLUTION_HEADERS
                        if header != "resolution_record_sha256"
                    }
                )
                if resolution_hash != expected_hash:
                    raise CategoryMappingValidationError(
                        f"A2.0 resolution row {row_number} has inconsistent resolution_record_sha256"
                    )
                rows.append(row)
    except (csv.Error, UnicodeError) as error:
        raise CategoryMappingValidationError(f"Cannot parse A2.0 resolution: {error}") from error
    return rows


def _source_tags(row: dict[str, str]) -> tuple[str, set[str], bool]:
    main_category = _nfc_trim(row["off_main_category"])
    categories_tags = _nfc_trim(row["off_categories_tags"])
    tags: set[str] = set()
    if categories_tags:
        tags.update(
            normalized
            for raw_tag in categories_tags.split(",")
            if (normalized := _normalize_tag(raw_tag))
        )
    return _normalize_tag(main_category), tags, bool(main_category or categories_tags)


def _mapping_decision(
    row: dict[str, str], ruleset: CategoryRuleset
) -> tuple[str, str, list[CategoryRule], list[str], str]:
    main_category, source_tags, has_evidence = _source_tags(row)
    if not has_evidence:
        return "", "unresolved", [], [], "no_category_evidence"

    main_matching = [
        rule
        for rule in ruleset.rules
        if main_category and main_category in rule.match_main_category_any
    ]
    tag_matching = [
        rule for rule in ruleset.rules if source_tags.intersection(rule.match_tags_any)
    ]
    matching = sorted(set(main_matching + tag_matching), key=lambda rule: rule.rule_id)
    matched_tags = sorted(
        ({main_category} if main_matching else set())
        | {
            tag
            for rule in tag_matching
            for tag in rule.match_tags_any
            if tag in source_tags
        }
    )
    if any(rule.action == "exclude" for rule in matching):
        return (
            "",
            "excluded",
            matching,
            matched_tags,
            "out_of_scope_for_initial_catalog",
        )

    main_map_targets = {
        rule.target_category for rule in main_matching if rule.action == "map"
    }
    if len(main_map_targets) > 1:
        return "", "review", matching, matched_tags, "ambiguous_target"
    if len(main_map_targets) == 1:
        return (
            next(iter(main_map_targets)) or "",
            "mapped",
            matching,
            matched_tags,
            "exact_main_category_rule",
        )

    map_targets = {rule.target_category for rule in tag_matching if rule.action == "map"}
    if len(map_targets) > 1:
        return "", "review", matching, matched_tags, "ambiguous_target"
    if len(map_targets) == 1:
        return (
            next(iter(map_targets)) or "",
            "mapped",
            matching,
            matched_tags,
            "exact_curated_tag_rule",
        )
    if any(rule.action == "review" for rule in matching):
        return "", "review", matching, matched_tags, "review_required"
    return "", "unresolved", [], [], "no_matching_rule"


def _mapping_row(row: dict[str, str], ruleset: CategoryRuleset) -> dict[str, str]:
    category, status, rules, matched_tags, reason = _mapping_decision(row, ruleset)
    output = {
        "barcode": row["barcode"],
        "off_main_category": row["off_main_category"],
        "off_categories_tags": row["off_categories_tags"],
        "cronos_category_candidate": category,
        "mapping_status": status,
        "mapping_rule_ids": "|".join(sorted(rule.rule_id for rule in rules)),
        "matched_off_tags": "|".join(matched_tags),
        "mapping_reason": reason,
        "ruleset_version": ruleset.ruleset_version,
        "ruleset_sha256": ruleset.ruleset_sha256,
        "resolution_record_sha256": row["resolution_record_sha256"],
        "category_mapping_record_sha256": "",
    }
    output["category_mapping_record_sha256"] = catalog_tool.record_hash(
        {
            header: output[header]
            for header in CATEGORY_MAPPING_HEADERS
            if header != "category_mapping_record_sha256"
        }
    )
    return output


def _metric_slug(category: str) -> str:
    ascii_text = unicodedata.normalize("NFKD", category).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "_", ascii_text.casefold()).strip("_")


def _build_metrics(
    resolution_rows: list[dict[str, str]],
    mapping_rows: list[dict[str, str]],
    ruleset: CategoryRuleset,
    categories: Sequence[str],
) -> dict[str, Any]:
    with_evidence = sum(
        bool(_nfc_trim(row["off_main_category"]) or _nfc_trim(row["off_categories_tags"]))
        for row in resolution_rows
    )
    metrics: dict[str, Any] = {
        "resolution_rows_total": len(resolution_rows),
        "mapping_rows_total": len(mapping_rows),
        "with_category_evidence": with_evidence,
        "without_category_evidence": len(resolution_rows) - with_evidence,
        "mapped": sum(row["mapping_status"] == "mapped" for row in mapping_rows),
        "unresolved": sum(row["mapping_status"] == "unresolved" for row in mapping_rows),
        "review": sum(row["mapping_status"] == "review" for row in mapping_rows),
        "excluded": sum(row["mapping_status"] == "excluded" for row in mapping_rows),
        "unresolved_no_category_evidence": sum(
            row["mapping_reason"] == "no_category_evidence" for row in mapping_rows
        ),
        "unresolved_no_matching_rule": sum(
            row["mapping_reason"] == "no_matching_rule" for row in mapping_rows
        ),
        "review_required": sum(
            row["mapping_reason"] == "review_required" for row in mapping_rows
        ),
        "review_ambiguous_target": sum(
            row["mapping_reason"] == "ambiguous_target" for row in mapping_rows
        ),
        "mapped_by_exact_main_category": sum(
            row["mapping_reason"] == "exact_main_category_rule" for row in mapping_rows
        ),
        "mapped_by_general_tag_rule": sum(
            row["mapping_reason"] == "exact_curated_tag_rule" for row in mapping_rows
        ),
        "excluded_out_of_scope": sum(
            row["mapping_reason"] == "out_of_scope_for_initial_catalog"
            for row in mapping_rows
        ),
        "rules_total": len(ruleset.rules),
        "rules_map": sum(rule.action == "map" for rule in ruleset.rules),
        "rules_review": sum(rule.action == "review" for rule in ruleset.rules),
        "rules_exclude": sum(rule.action == "exclude" for rule in ruleset.rules),
        "ruleset_version": ruleset.ruleset_version,
        "ruleset_sha256": ruleset.ruleset_sha256,
        "network_access": False,
        "database_access": False,
        "uuid_generation": False,
    }
    for category in categories:
        metrics[f"mapped_{_metric_slug(category)}"] = sum(
            row["mapping_status"] == "mapped"
            and row["cronos_category_candidate"] == category
            for row in mapping_rows
        )
    return metrics


def _write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=CATEGORY_MAPPING_HEADERS,
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(rows)


def _split_pipe_values(value: str, field_name: str, row_number: int) -> list[str]:
    if not value:
        return []
    values = value.split("|")
    if values != sorted(set(values)) or any(not item for item in values):
        raise CategoryMappingValidationError(
            f"Mapping row {row_number} has non-deterministic {field_name}"
        )
    return values


def _validate_mapping_output(
    path: Path,
    *,
    expected_barcodes: set[str],
    categories: Sequence[str],
    ruleset: CategoryRuleset,
) -> None:
    try:
        handle = path.open("r", encoding="utf-8-sig", newline="")
    except OSError as error:
        raise CategoryMappingToolError(f"Cannot read temporary mapping output {path}: {error}") from error

    with handle:
        try:
            reader = csv.DictReader(handle, strict=True)
            if reader.fieldnames != CATEGORY_MAPPING_HEADERS:
                raise CategoryMappingValidationError("Category mapping output header is invalid")
            rows = list(reader)
        except (csv.Error, UnicodeError) as error:
            raise CategoryMappingValidationError(
                f"Cannot parse category mapping output: {error}"
            ) from error

    if len(rows) != len(expected_barcodes):
        raise CategoryMappingValidationError(
            "Category mapping output row count differs from A2.0 resolution"
        )
    barcodes = [row["barcode"] for row in rows]
    if len(barcodes) != len(set(barcodes)):
        raise CategoryMappingValidationError("Category mapping output contains duplicate barcodes")
    if set(barcodes) != expected_barcodes:
        raise CategoryMappingValidationError(
            "Category mapping output barcode set differs from A2.0 resolution"
        )
    if barcodes != sorted(barcodes):
        raise CategoryMappingValidationError("Category mapping output is not ordered by barcode")

    allowed_categories = set(categories)
    rule_ids = {rule.rule_id for rule in ruleset.rules}
    for row_number, row in enumerate(rows, start=2):
        status = row["mapping_status"]
        category = row["cronos_category_candidate"]
        reason = row["mapping_reason"]
        if status not in MAPPING_STATUSES:
            raise CategoryMappingValidationError(f"Mapping row {row_number} has invalid status")
        if category and category not in allowed_categories:
            raise CategoryMappingValidationError(
                f"Mapping row {row_number} category is outside the P1.2 vocabulary"
            )
        if status == "mapped" and not category:
            raise CategoryMappingValidationError(
                f"Mapped row {row_number} requires a Cronos category"
            )
        if status != "mapped" and category:
            raise CategoryMappingValidationError(
                f"Non-mapped row {row_number} must not contain a Cronos category"
            )
        if reason not in MAPPING_REASONS:
            raise CategoryMappingValidationError(f"Mapping row {row_number} has invalid reason")
        if reason not in REASONS_BY_STATUS[status]:
            raise CategoryMappingValidationError(
                f"Mapping row {row_number} reason is incompatible with its status"
            )
        matched_rule_ids = _split_pipe_values(
            row["mapping_rule_ids"], "mapping_rule_ids", row_number
        )
        if any(rule_id not in rule_ids for rule_id in matched_rule_ids):
            raise CategoryMappingValidationError(
                f"Mapping row {row_number} references an unknown rule"
            )
        _split_pipe_values(row["matched_off_tags"], "matched_off_tags", row_number)
        if row["ruleset_version"] != ruleset.ruleset_version:
            raise CategoryMappingValidationError(
                f"Mapping row {row_number} has inconsistent ruleset_version"
            )
        if row["ruleset_sha256"] != ruleset.ruleset_sha256:
            raise CategoryMappingValidationError(
                f"Mapping row {row_number} has inconsistent ruleset_sha256"
            )
        if not SHA256_RE.fullmatch(row["resolution_record_sha256"]):
            raise CategoryMappingValidationError(
                f"Mapping row {row_number} has invalid resolution_record_sha256"
            )
        if not SHA256_RE.fullmatch(row["category_mapping_record_sha256"]):
            raise CategoryMappingValidationError(
                f"Mapping row {row_number} has invalid category_mapping_record_sha256"
            )
        expected_hash = catalog_tool.record_hash(
            {
                header: row[header]
                for header in CATEGORY_MAPPING_HEADERS
                if header != "category_mapping_record_sha256"
            }
        )
        if row["category_mapping_record_sha256"] != expected_hash:
            raise CategoryMappingValidationError(
                f"Mapping row {row_number} has inconsistent category_mapping_record_sha256"
            )


def _temporary_output(final_path: Path) -> Path:
    final_path.parent.mkdir(parents=True, exist_ok=True)
    handle = tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=final_path.parent,
        prefix=f".{final_path.name}.",
        suffix=".tmp",
        delete=False,
    )
    path = Path(handle.name)
    handle.close()
    return path


def map_categories(
    *,
    resolution_path: Path,
    rules_path: Path,
    output_path: Path,
    metrics_path: Path,
    vocabularies_path: Path = catalog_tool.DEFAULT_CONFIG,
) -> dict[str, Any]:
    paths = [
        Path(path).expanduser().resolve()
        for path in (resolution_path, rules_path, output_path, metrics_path)
    ]
    resolution_path, rules_path, output_path, metrics_path = paths
    vocabularies_path = Path(vocabularies_path).expanduser().resolve()
    if output_path == metrics_path:
        raise CategoryMappingToolError("--output and --metrics must be distinct")
    if output_path in (resolution_path, rules_path) or metrics_path in (
        resolution_path,
        rules_path,
    ):
        raise CategoryMappingToolError("Output paths must not overwrite inputs")

    categories = _load_categories(vocabularies_path)
    ruleset = load_ruleset(rules_path, categories)
    resolution_rows = _load_resolution(resolution_path)
    resolution_rows.sort(key=lambda row: row["barcode"])
    mapping_rows = [_mapping_row(row, ruleset) for row in resolution_rows]
    metrics = _build_metrics(resolution_rows, mapping_rows, ruleset, categories)

    final_and_temporary: list[tuple[Path, Path]] = []
    try:
        output_temp = _temporary_output(output_path)
        final_and_temporary.append((output_path, output_temp))
        metrics_temp = _temporary_output(metrics_path)
        final_and_temporary.append((metrics_path, metrics_temp))
        _write_csv(output_temp, mapping_rows)
        _validate_mapping_output(
            output_temp,
            expected_barcodes={row["barcode"] for row in resolution_rows},
            categories=categories,
            ruleset=ruleset,
        )
        metrics_temp.write_text(
            json.dumps(metrics, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
            encoding="utf-8",
        )
        os.replace(metrics_temp, metrics_path)
        os.replace(output_temp, output_path)
    finally:
        for _, temporary_path in final_and_temporary:
            try:
                temporary_path.unlink(missing_ok=True)
            except OSError:
                pass
    return metrics


def human_report(metrics: dict[str, Any], categories: Sequence[str]) -> str:
    lines = [
        "Category Mapping v1: SUCCESS",
        f"Resolution rows: {metrics['resolution_rows_total']}",
        f"With category evidence: {metrics['with_category_evidence']}",
        f"Mapped: {metrics['mapped']}",
        f"Review: {metrics['review']}",
        f"Excluded: {metrics['excluded']}",
        f"Unresolved: {metrics['unresolved']}",
        "",
        "Mapped:",
    ]
    lines.extend(
        f"  {category}: {metrics[f'mapped_{_metric_slug(category)}']}"
        for category in categories
    )
    lines.extend(
        [
            "",
            "Network access: none",
            "Database access: none",
            "UUID generation: none",
        ]
    )
    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    mapping = subparsers.add_parser("map", help="Build an A2.1 category mapping proposal")
    mapping.add_argument("--resolution", required=True, type=_path)
    mapping.add_argument("--rules", required=True, type=_path)
    mapping.add_argument("--output", required=True, type=_path)
    mapping.add_argument("--metrics", required=True, type=_path)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        metrics = map_categories(
            resolution_path=args.resolution,
            rules_path=args.rules,
            output_path=args.output,
            metrics_path=args.metrics,
        )
        print(human_report(metrics, _load_categories()))
        return 0
    except CategoryMappingValidationError as error:
        print(f"VALIDATION ERROR: {error}", file=sys.stderr)
        return 1
    except (CategoryMappingToolError, OSError) as error:
        print(f"TOOL ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
