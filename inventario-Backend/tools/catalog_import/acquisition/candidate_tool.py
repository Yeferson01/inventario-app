#!/usr/bin/env python3
"""Validate persistable catalog-acquisition candidates without side effects."""

from __future__ import annotations

import argparse
import csv
import re
import sys
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Sequence


CATALOG_IMPORT_DIR = Path(__file__).resolve().parents[1]
if str(CATALOG_IMPORT_DIR) not in sys.path:
    sys.path.insert(0, str(CATALOG_IMPORT_DIR))

import catalog_tool  # noqa: E402


CANDIDATE_HEADERS = [
    "raw_barcode",
    "barcode",
    "barcode_type",
    "name_if_known",
    "brand_if_known",
    "source",
    "source_channel",
    "source_reference",
    "source_record_id",
    "retrieved_at",
    "rights_class",
    "rights_reference",
    "can_persist_candidate",
    "candidate_confidence",
    "colombia_evidence_type",
    "colombia_evidence_count",
    "source_content_sha256",
    "notes",
]

REQUIRED_FIELDS = [
    "raw_barcode",
    "barcode",
    "barcode_type",
    "source",
    "source_channel",
    "source_reference",
    "retrieved_at",
    "rights_class",
    "rights_reference",
    "can_persist_candidate",
    "candidate_confidence",
    "colombia_evidence_type",
    "colombia_evidence_count",
    "source_content_sha256",
]

SOURCE_CHANNELS = {
    "merchant_inventory",
    "pos_export",
    "supplier_feed",
    "manufacturer_feed",
    "open_icecat",
    "gdsn",
    "manual_research",
    "other_authorized",
}

CANDIDATE_CONFIDENCE_VALUES = {"high", "medium"}

COLOMBIA_EVIDENCE_TYPES = {
    "merchant_inventory",
    "authorized_distributor",
    "manufacturer_colombia_portfolio",
    "gdsn_target_market",
    "other_documented",
}

SHA256_RE = re.compile(r"^[0-9a-fA-F]{64}$")
BASE10_INTEGER_RE = re.compile(r"^[0-9]+$")

DEFAULT_INPUT = CATALOG_IMPORT_DIR / "datasets" / "catalog_candidates.csv"
DEFAULT_VOCABULARIES = CATALOG_IMPORT_DIR / "config" / "vocabularies.json"


class CandidateToolError(Exception):
    """Usage, I/O, or malformed configuration error (exit code 2)."""


@dataclass(frozen=True)
class CandidateIssue:
    code: str
    file: str
    row: int | None
    field: str | None
    message: str

    def to_dict(self) -> dict[str, Any]:
        return {key: value for key, value in asdict(self).items() if value is not None}


def _path(value: str) -> Path:
    return Path(value).expanduser().resolve()


def _visible(value: Any) -> str:
    return catalog_tool.normalize_visible_text(value)


def _read_candidates(path: Path) -> tuple[list[dict[str, str]], list[CandidateIssue]]:
    try:
        handle = path.open("r", encoding="utf-8-sig", newline="")
    except OSError as error:
        raise CandidateToolError(f"Cannot read candidate CSV {path}: {error}") from error

    with handle:
        try:
            reader = csv.DictReader(handle, strict=True)
            actual_headers = reader.fieldnames or []
            issues: list[CandidateIssue] = []
            if actual_headers != CANDIDATE_HEADERS:
                issues.append(
                    CandidateIssue(
                        "invalid_header",
                        path.name,
                        1,
                        None,
                        "CSV header does not match the candidate acquisition contract",
                    )
                )

            rows: list[dict[str, str]] = []
            for raw_row in reader:
                if None in raw_row:
                    issues.append(
                        CandidateIssue(
                            "extra_csv_values",
                            path.name,
                            reader.line_num,
                            None,
                            "CSV row contains more values than the declared header",
                        )
                    )
                row = {header: raw_row.get(header, "") or "" for header in CANDIDATE_HEADERS}
                raw_values = [
                    item
                    for value in raw_row.values()
                    for item in (value if isinstance(value, list) else [value])
                ]
                if any(_visible(value) for value in raw_values):
                    row["__row_number__"] = str(reader.line_num)
                    rows.append(row)
            return rows, issues
        except (csv.Error, UnicodeError) as error:
            raise CandidateToolError(f"Cannot parse candidate CSV {path}: {error}") from error


def _load_sources(path: Path) -> set[str]:
    try:
        vocabularies = catalog_tool._load_vocabularies(path)  # noqa: SLF001
    except catalog_tool.CatalogToolError as error:
        raise CandidateToolError(str(error)) from error
    return set(vocabularies["sources"])


def _add_issue(
    issues: list[CandidateIssue],
    *,
    code: str,
    file_name: str,
    row_number: int,
    field: str,
    message: str,
) -> None:
    issues.append(CandidateIssue(code, file_name, row_number, field, message))


def _validate_timestamp(value: str) -> bool:
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return False
    return parsed.tzinfo is not None and parsed.utcoffset() is not None


def _normalize_and_validate_row(
    row: dict[str, str],
    *,
    file_name: str,
    allowed_sources: set[str],
    issues: list[CandidateIssue],
) -> dict[str, Any]:
    row_number = int(row["__row_number__"])
    visible = {field: _visible(row[field]) for field in CANDIDATE_HEADERS}

    for field in REQUIRED_FIELDS:
        if not visible[field]:
            _add_issue(
                issues,
                code="missing_required_field",
                file_name=file_name,
                row_number=row_number,
                field=field,
                message=f"Required candidate field is empty: {field}",
            )

    raw_barcode = row["raw_barcode"]
    barcode = row["barcode"]
    barcode_type = visible["barcode_type"]
    if visible["raw_barcode"] and visible["barcode"] and barcode != raw_barcode.strip():
        _add_issue(
            issues,
            code="barcode_not_raw_trim",
            file_name=file_name,
            row_number=row_number,
            field="barcode",
            message="barcode must equal raw_barcode after removing exterior whitespace only",
        )

    if visible["barcode"] and barcode_type:
        barcode_error = catalog_tool.validate_barcode_shape(barcode, barcode_type)
        if barcode_error:
            _add_issue(
                issues,
                code="invalid_barcode",
                file_name=file_name,
                row_number=row_number,
                field="barcode",
                message=barcode_error,
            )

    if visible["source"] and visible["source"] not in allowed_sources:
        _add_issue(
            issues,
            code="invalid_source",
            file_name=file_name,
            row_number=row_number,
            field="source",
            message="source is outside the P1.2 controlled vocabulary",
        )

    if visible["source_channel"] and visible["source_channel"] not in SOURCE_CHANNELS:
        _add_issue(
            issues,
            code="invalid_source_channel",
            file_name=file_name,
            row_number=row_number,
            field="source_channel",
            message="source_channel is outside the acquisition vocabulary",
        )

    if visible["can_persist_candidate"] and visible["can_persist_candidate"] != "true":
        _add_issue(
            issues,
            code="candidate_not_persistable",
            file_name=file_name,
            row_number=row_number,
            field="can_persist_candidate",
            message="can_persist_candidate must be exactly true",
        )

    if (
        visible["candidate_confidence"]
        and visible["candidate_confidence"] not in CANDIDATE_CONFIDENCE_VALUES
    ):
        _add_issue(
            issues,
            code="invalid_candidate_confidence",
            file_name=file_name,
            row_number=row_number,
            field="candidate_confidence",
            message="candidate_confidence must be high or medium",
        )

    if visible["retrieved_at"] and not _validate_timestamp(visible["retrieved_at"]):
        _add_issue(
            issues,
            code="invalid_retrieved_at",
            file_name=file_name,
            row_number=row_number,
            field="retrieved_at",
            message="retrieved_at must be an ISO-8601 timestamp with an explicit timezone",
        )

    sha256 = visible["source_content_sha256"]
    if sha256 and not SHA256_RE.fullmatch(sha256):
        _add_issue(
            issues,
            code="invalid_source_content_sha256",
            file_name=file_name,
            row_number=row_number,
            field="source_content_sha256",
            message="source_content_sha256 must contain exactly 64 hexadecimal characters",
        )

    evidence_count = visible["colombia_evidence_count"]
    if evidence_count:
        if not BASE10_INTEGER_RE.fullmatch(evidence_count) or int(evidence_count, 10) < 1:
            _add_issue(
                issues,
                code="invalid_colombia_evidence_count",
                file_name=file_name,
                row_number=row_number,
                field="colombia_evidence_count",
                message="colombia_evidence_count must be a base-10 integer greater than or equal to 1",
            )

    evidence_type = visible["colombia_evidence_type"]
    if evidence_type and evidence_type not in COLOMBIA_EVIDENCE_TYPES:
        _add_issue(
            issues,
            code="invalid_colombia_evidence_type",
            file_name=file_name,
            row_number=row_number,
            field="colombia_evidence_type",
            message="colombia_evidence_type is outside the acquisition vocabulary",
        )

    return {
        "source_row": row_number,
        "raw_barcode": raw_barcode,
        "barcode": barcode,
        "barcode_type": barcode_type,
        "name_if_known": _visible(row["name_if_known"]),
        "brand_if_known": _visible(row["brand_if_known"]),
        "source": visible["source"],
        "source_channel": visible["source_channel"],
        "source_reference": visible["source_reference"],
        "source_record_id": visible["source_record_id"],
        "retrieved_at": visible["retrieved_at"],
        "rights_class": visible["rights_class"],
        "rights_reference": visible["rights_reference"],
        "can_persist_candidate": visible["can_persist_candidate"],
        "candidate_confidence": visible["candidate_confidence"],
        "colombia_evidence_type": evidence_type,
        "colombia_evidence_count": evidence_count,
        "source_content_sha256": sha256.lower(),
        "notes": _visible(row["notes"]),
    }


def validate_candidates(
    *,
    input_path: Path = DEFAULT_INPUT,
    vocabularies_path: Path = DEFAULT_VOCABULARIES,
) -> dict[str, Any]:
    allowed_sources = _load_sources(vocabularies_path)
    rows, issues = _read_candidates(input_path)

    normalized_rows = [
        _normalize_and_validate_row(
            row,
            file_name=input_path.name,
            allowed_sources=allowed_sources,
            issues=issues,
        )
        for row in rows
    ]

    rows_by_barcode: dict[str, list[int]] = {}
    for row in normalized_rows:
        barcode = row["barcode"]
        if barcode:
            rows_by_barcode.setdefault(barcode, []).append(row["source_row"])

    duplicate_barcodes = sorted(
        barcode for barcode, row_numbers in rows_by_barcode.items() if len(row_numbers) > 1
    )
    for barcode in duplicate_barcodes:
        for row_number in rows_by_barcode[barcode]:
            _add_issue(
                issues,
                code="duplicate_barcode",
                file_name=input_path.name,
                row_number=row_number,
                field="barcode",
                message=f"Duplicate candidate barcode: {barcode}",
            )

    issues.sort(key=lambda issue: (issue.row or 0, issue.field or "", issue.code))
    candidate_row_numbers = {row["source_row"] for row in normalized_rows}
    invalid_row_numbers = {issue.row for issue in issues if issue.row in candidate_row_numbers}
    invalid_rows = len(invalid_row_numbers)

    return {
        "valid": not issues,
        "candidate_rows": len(rows),
        "valid_rows": len(rows) - invalid_rows,
        "invalid_rows": invalid_rows,
        "blocking_error_count": len(issues),
        "blocking_errors": [issue.to_dict() for issue in issues],
        "duplicate_barcode_count": len(duplicate_barcodes),
        "duplicate_barcodes": duplicate_barcodes,
        "normalized_preview": normalized_rows,
        "network_access": False,
        "database_access": False,
    }


def human_report(report: dict[str, Any]) -> str:
    status = "VALID" if report["valid"] else "INVALID"
    lines = [
        f"Catalog candidates: {status}",
        f"Candidate rows: {report['candidate_rows']}",
        f"Valid rows: {report['valid_rows']}",
        f"Invalid rows: {report['invalid_rows']}",
        f"Blocking errors: {report['blocking_error_count']}",
        f"Duplicate barcodes: {report['duplicate_barcode_count']}",
        "Network access: none",
        "Database access: none",
    ]
    for issue in report["blocking_errors"]:
        location = issue["file"]
        if "row" in issue:
            location += f":{issue['row']}"
        if "field" in issue:
            location += f" [{issue['field']}]"
        lines.append(f"ERROR {issue['code']} {location}: {issue['message']}")
    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate_parser = subparsers.add_parser("validate", help="Validate without modifying candidates")
    validate_parser.add_argument("--input", type=_path, default=DEFAULT_INPUT)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        report = validate_candidates(input_path=args.input)
        print(human_report(report))
        return 0 if report["valid"] else 1
    except (CandidateToolError, catalog_tool.CatalogToolError) as error:
        print(f"TOOL ERROR: {error}", file=sys.stderr)
        return 2
    except OSError as error:
        print(f"I/O ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
