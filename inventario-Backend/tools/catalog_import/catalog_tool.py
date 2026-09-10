#!/usr/bin/env python3
"""Local-only tooling for the CronosManagement master catalog dataset."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
import unicodedata
import uuid
from dataclasses import asdict, dataclass, field as dataclass_field
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any, Iterable, Sequence


TOOL_VERSION = "1.0.0"
SCHEMA_VERSION = 1

MASTER_HEADERS = [
    "master_product_id",
    "primary_barcode",
    "barcode_type",
    "name",
    "brand",
    "manufacturer",
    "category_name",
    "subcategory_name",
    "package_size",
    "package_unit",
    "unit_type",
    "description",
    "source",
    "verification_status",
    "confidence_score",
    "source_reference",
    "image_source_key",
    "image_license",
    "image_attribution",
]

BARCODE_HEADERS = [
    "barcode_id",
    "master_product_id",
    "barcode",
    "barcode_type",
    "is_primary",
    "source",
    "confidence_score",
    "source_reference",
]

REJECTED_INVALID_BARCODE_HEADERS = [*MASTER_HEADERS, "rejection_reason"]
REJECTED_EXACT_MASTER_HEADERS = [
    *MASTER_HEADERS,
    "rejection_reason",
    "duplicate_group_id",
]
REJECTED_EXACT_BARCODE_HEADERS = [
    *BARCODE_HEADERS,
    "rejection_reason",
    "duplicate_group_id",
]
REJECTED_PREFLIGHT_REVIEW_MASTER_HEADERS = [
    *MASTER_HEADERS,
    "rejection_reason",
    "planner_reason",
]
REJECTED_PREFLIGHT_REVIEW_BARCODE_HEADERS = [
    *BARCODE_HEADERS,
    "rejection_reason",
    "planner_reason",
]
REJECTED_PREFLIGHT_CONFLICT_MASTER_HEADERS = [
    *MASTER_HEADERS,
    "rejection_reason",
    "planner_reason",
    "hosted_owner_master_id",
    "hosted_barcode_id",
]
REJECTED_PREFLIGHT_CONFLICT_BARCODE_HEADERS = [
    *BARCODE_HEADERS,
    "rejection_reason",
    "planner_reason",
    "hosted_owner_master_id",
    "hosted_barcode_id",
]

REQUIRED_MASTER_FIELDS = [
    "master_product_id",
    "primary_barcode",
    "barcode_type",
    "name",
    "category_name",
    "unit_type",
    "source",
    "verification_status",
    "confidence_score",
    "source_reference",
]

REQUIRED_BARCODE_FIELDS = BARCODE_HEADERS

PROHIBITED_COLUMN_NAMES = {
    "purchase_price",
    "sale_price",
    "stock",
    "stock_quantity",
    "minimum_stock",
    "business_id",
    "branch_id",
    "supplier_id",
    "api_secret",
    "service_role_key",
    "supabase_service_role_key",
    "cloudinary_api_secret",
}

SECRET_VALUE_PATTERNS = (
    re.compile(r"(?i)\bapi[_ -]?secret\b\s*[:=]"),
    re.compile(r"(?i)\bservice[_ -]?role(?:[_ -]?key)?\b\s*[:=]"),
    re.compile(r"(?i)\bcloudinary_url\b\s*[:=]"),
    re.compile(r"(?i)\bsb_secret_[A-Za-z0-9._-]{16,}\b"),
    re.compile(r"(?i)\bsk-[A-Za-z0-9_-]{20,}\b"),
    re.compile(r"(?i)\b(?:postgres|postgresql)://[^\s:/]+:[^\s@]+@"),
    re.compile(r"\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\b"),
)

SCIENTIFIC_NOTATION_RE = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)[eE][+-]?\d+$")
DECIMAL_RE = re.compile(r"^[+]?(?:0|[1-9]\d*)(?:\.\d+)?$")
UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)

BASE_DIR = Path(__file__).resolve().parent
DEFAULT_CONFIG = BASE_DIR / "config" / "vocabularies.json"
DEFAULT_DATASET_DIR = BASE_DIR / "datasets"
DEFAULT_MASTERS = DEFAULT_DATASET_DIR / "master_catalog_seed.csv"
DEFAULT_BARCODES = DEFAULT_DATASET_DIR / "master_catalog_barcodes.csv"
DEFAULT_MANIFEST = DEFAULT_DATASET_DIR / "catalog_dataset_manifest.json"
DEFAULT_BACKUP_DIR = Path(tempfile.gettempdir()) / "CronosManagement" / "catalog_import_backups"
DEFAULT_REJECTED_INVALID_BARCODE_REPORT = (
    BASE_DIR / "reports" / "rejected_invalid_barcode_rows.csv"
)
DEFAULT_REJECTED_EXACT_MASTER_REPORT = (
    BASE_DIR / "reports" / "rejected_exact_semantic_duplicate_masters.csv"
)
DEFAULT_REJECTED_EXACT_BARCODE_REPORT = (
    BASE_DIR / "reports" / "rejected_exact_semantic_duplicate_barcodes.csv"
)
DEFAULT_PREFLIGHT_PLAN = BASE_DIR / "reports" / "hosted-catalog-import-plan.json"
DEFAULT_PREFLIGHT_SNAPSHOT = BASE_DIR / "reports" / "hosted-catalog-snapshot.json"
DEFAULT_REJECTED_PREFLIGHT_REVIEW_MASTER_REPORT = (
    BASE_DIR / "reports" / "rejected_near_semantic_review_masters.csv"
)
DEFAULT_REJECTED_PREFLIGHT_REVIEW_BARCODE_REPORT = (
    BASE_DIR / "reports" / "rejected_near_semantic_review_barcodes.csv"
)
DEFAULT_REJECTED_PREFLIGHT_CONFLICT_MASTER_REPORT = (
    BASE_DIR / "reports" / "rejected_hosted_conflict_masters.csv"
)
DEFAULT_REJECTED_PREFLIGHT_CONFLICT_BARCODE_REPORT = (
    BASE_DIR / "reports" / "rejected_hosted_conflict_barcodes.csv"
)


class CatalogToolError(Exception):
    """Usage, I/O, or malformed configuration error (exit code 2)."""


@dataclass(frozen=True)
class Issue:
    severity: str
    code: str
    file: str
    row: int | None
    field: str | None
    message: str
    details: dict[str, Any] = dataclass_field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {key: value for key, value in asdict(self).items() if value not in (None, {})}


def normalize_visible_text(value: Any) -> str:
    """Normalize display text without destroying accents or letter case."""
    text = "" if value is None else str(value)
    return re.sub(r"\s+", " ", unicodedata.normalize("NFC", text)).strip()


def normalize_semantic_text(value: Any) -> str:
    return normalize_visible_text(value).casefold()


def normalize_barcode(value: Any) -> str:
    """Match private.normalize_barcode in the PostgreSQL catalog contract."""
    raw = normalize_visible_text(value)
    return re.sub(r"[^A-Za-z0-9]", "", raw).upper()


def canonical_decimal(value: Any, *, field_name: str) -> str:
    raw = normalize_visible_text(value)
    if not raw:
        return ""
    if SCIENTIFIC_NOTATION_RE.fullmatch(raw):
        raise ValueError(f"{field_name} must not use scientific notation")
    if not DECIMAL_RE.fullmatch(raw):
        raise ValueError(f"{field_name} must be a non-negative base-10 decimal")
    try:
        number = Decimal(raw)
    except InvalidOperation as error:
        raise ValueError(f"{field_name} is not a valid decimal") from error
    normalized = format(number.normalize(), "f")
    if "." in normalized:
        normalized = normalized.rstrip("0").rstrip(".")
    return normalized or "0"


def is_valid_uuid(value: str) -> bool:
    if not UUID_RE.fullmatch(value):
        return False
    try:
        return str(uuid.UUID(value)) == value.lower()
    except ValueError:
        return False


def gtin_check_digit_is_valid(value: str) -> bool:
    if not value.isdigit() or len(value) not in (8, 12, 13, 14):
        return False
    payload = value[:-1]
    total = 0
    for offset, digit in enumerate(reversed(payload), start=1):
        total += int(digit) * (3 if offset % 2 == 1 else 1)
    expected = (10 - (total % 10)) % 10
    return expected == int(value[-1])


def validate_barcode_shape(value: str, barcode_type: str) -> str | None:
    expected_lengths = {"ean8": 8, "upc": 12, "ean13": 13, "gtin": 14}
    if barcode_type in ("internal", "local_sku"):
        return "Internal and local SKU codes are not allowed in the global seed"
    expected = expected_lengths.get(barcode_type)
    if expected is None:
        return f"Unsupported global barcode_type: {barcode_type or '<empty>'}"
    if SCIENTIFIC_NOTATION_RE.fullmatch(value):
        return "Barcode must not use scientific notation"
    if not value.isdigit():
        return f"{barcode_type} must contain digits only"
    if len(value) != expected:
        return f"{barcode_type} must contain exactly {expected} digits"
    if not gtin_check_digit_is_valid(value):
        return f"{barcode_type} checksum is invalid"
    return None


def stable_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def record_hash(record: dict[str, Any]) -> str:
    return hashlib.sha256(stable_json(record).encode("utf-8")).hexdigest()


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise CatalogToolError(f"Cannot read JSON file {path}: {error}") from error
    if not isinstance(value, dict):
        raise CatalogToolError(f"JSON file must contain an object: {path}")
    return value


def _read_csv(path: Path, expected_headers: Sequence[str]) -> tuple[list[dict[str, str]], list[Issue]]:
    try:
        handle = path.open("r", encoding="utf-8-sig", newline="")
    except OSError as error:
        raise CatalogToolError(f"Cannot read CSV file {path}: {error}") from error

    with handle:
        try:
            reader = csv.DictReader(handle)
            actual_headers = reader.fieldnames or []
            issues = _header_issues(path, actual_headers, expected_headers)
            rows: list[dict[str, str]] = []
            for raw in reader:
                if None in raw:
                    issues.append(
                        Issue(
                            "error",
                            "extra_csv_values",
                            path.name,
                            reader.line_num,
                            None,
                            "CSV row contains more values than the declared header",
                        )
                    )
                row = {header: raw.get(header, "") or "" for header in expected_headers}
                if any(normalize_visible_text(value) for value in row.values()):
                    row["__row_number__"] = str(reader.line_num)
                    rows.append(row)
            return rows, issues
        except csv.Error as error:
            raise CatalogToolError(f"Malformed CSV file {path}: {error}") from error


def _header_issues(path: Path, actual: Sequence[str], expected: Sequence[str]) -> list[Issue]:
    issues: list[Issue] = []
    lowered = {normalize_visible_text(value).casefold() for value in actual if value is not None}
    for column in sorted(lowered & PROHIBITED_COLUMN_NAMES):
        issues.append(
            Issue(
                "error",
                "prohibited_column",
                path.name,
                1,
                column,
                f"Operational or secret column is prohibited in the master catalog: {column}",
            )
        )
    if list(actual) != list(expected):
        missing = [column for column in expected if column not in actual]
        unexpected = [column for column in actual if column not in expected]
        issues.append(
            Issue(
                "error",
                "invalid_header",
                path.name,
                1,
                None,
                "CSV header does not match the versioned contract",
                {"expected": list(expected), "missing": missing, "unexpected": unexpected},
            )
        )
    return issues


def _load_vocabularies(path: Path) -> dict[str, Any]:
    data = _read_json(path)
    required_lists = [
        "categories",
        "package_units",
        "unit_types",
        "quantified_unit_types",
        "sources",
        "verification_statuses",
        "barcode_types",
        "image_licenses",
        "image_attribution_required_for",
    ]
    for key in required_lists:
        value = data.get(key)
        if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
            raise CatalogToolError(f"Vocabulary '{key}' must be a JSON string array")
    return data


def _load_manifest(path: Path) -> dict[str, Any]:
    data = _read_json(path)
    if data.get("schema_version") != SCHEMA_VERSION:
        raise CatalogToolError(
            f"Unsupported dataset schema_version: {data.get('schema_version')!r}; expected {SCHEMA_VERSION}"
        )
    if not normalize_visible_text(data.get("dataset_version")):
        raise CatalogToolError("Manifest dataset_version is required")
    if not isinstance(data.get("tool"), dict) or not normalize_visible_text(data["tool"].get("version")):
        raise CatalogToolError("Manifest tool.version is required")
    return data


def _contains_secret(value: str) -> bool:
    return any(pattern.search(value) for pattern in SECRET_VALUE_PATTERNS)


def _add_required_issues(
    row: dict[str, str], fields: Iterable[str], file_name: str, row_number: int, issues: list[Issue]
) -> None:
    for field_name in fields:
        if not normalize_visible_text(row.get(field_name)):
            issues.append(
                Issue(
                    "error",
                    "missing_required_field",
                    file_name,
                    row_number,
                    field_name,
                    f"Required field is empty: {field_name}",
                )
            )


def _validate_secret_values(
    row: dict[str, str], file_name: str, row_number: int, issues: list[Issue]
) -> None:
    for field_name, value in row.items():
        if field_name.startswith("__"):
            continue
        if _contains_secret(value):
            issues.append(
                Issue(
                    "error",
                    "prohibited_secret_value",
                    file_name,
                    row_number,
                    field_name,
                    "Possible API secret or token must not be stored in the dataset",
                )
            )


def _issue_for_uuid(
    value: str, file_name: str, row_number: int, field_name: str, issues: list[Issue]
) -> str:
    normalized = normalize_visible_text(value).lower()
    if normalized and not is_valid_uuid(normalized):
        issues.append(
            Issue(
                "error",
                "invalid_uuid",
                file_name,
                row_number,
                field_name,
                f"Invalid UUID in {field_name}",
            )
        )
    return normalized


def _issue_for_decimal(
    value: str,
    file_name: str,
    row_number: int,
    field_name: str,
    issues: list[Issue],
    *,
    required: bool,
    minimum_exclusive: Decimal | None = None,
    maximum_inclusive: Decimal | None = None,
) -> str:
    raw = normalize_visible_text(value)
    if not raw and not required:
        return ""
    try:
        normalized = canonical_decimal(raw, field_name=field_name)
        number = Decimal(normalized)
        if minimum_exclusive is not None and number <= minimum_exclusive:
            raise ValueError(f"{field_name} must be greater than {minimum_exclusive}")
        if maximum_inclusive is not None and number > maximum_inclusive:
            raise ValueError(f"{field_name} must not exceed {maximum_inclusive}")
        return normalized
    except (ValueError, InvalidOperation) as error:
        issues.append(
            Issue(
                "error",
                "invalid_decimal",
                file_name,
                row_number,
                field_name,
                str(error),
            )
        )
        return raw


def _validate_barcode(
    raw_value: str,
    barcode_type: str,
    file_name: str,
    row_number: int,
    field_name: str,
    issues: list[Issue],
) -> str:
    visible = normalize_visible_text(raw_value)
    if SCIENTIFIC_NOTATION_RE.fullmatch(visible):
        issues.append(
            Issue(
                "error",
                "scientific_notation_barcode",
                file_name,
                row_number,
                field_name,
                "Barcode must be stored as text; scientific notation is forbidden",
            )
        )
        return visible
    normalized = normalize_barcode(visible)
    if not normalized:
        issues.append(
            Issue(
                "error",
                "empty_barcode",
                file_name,
                row_number,
                field_name,
                "Barcode is empty after backend-compatible normalization",
            )
        )
        return normalized
    shape_error = validate_barcode_shape(normalized, barcode_type)
    if shape_error:
        issues.append(
            Issue(
                "error",
                "invalid_barcode",
                file_name,
                row_number,
                field_name,
                shape_error,
                {"barcode_type": barcode_type, "normalized": normalized},
            )
        )
    return normalized


def _validate_vocabulary(
    value: str,
    vocabulary: Sequence[str],
    file_name: str,
    row_number: int,
    field_name: str,
    issues: list[Issue],
) -> str:
    normalized = normalize_visible_text(value)
    if normalized and normalized not in vocabulary:
        issues.append(
            Issue(
                "error",
                "invalid_vocabulary_value",
                file_name,
                row_number,
                field_name,
                f"Value is outside the controlled vocabulary: {normalized}",
                {"allowed": list(vocabulary)},
            )
        )
    return normalized


def _normalize_master(
    row: dict[str, str], vocab: dict[str, Any], file_name: str, issues: list[Issue]
) -> dict[str, Any]:
    row_number = int(row["__row_number__"])
    _add_required_issues(row, REQUIRED_MASTER_FIELDS, file_name, row_number, issues)
    _validate_secret_values(row, file_name, row_number, issues)

    normalized: dict[str, Any] = {
        "master_product_id": _issue_for_uuid(
            row["master_product_id"], file_name, row_number, "master_product_id", issues
        ),
        "primary_barcode": normalize_visible_text(row["primary_barcode"]),
        "barcode_type": normalize_visible_text(row["barcode_type"]).lower(),
        "name": normalize_visible_text(row["name"]),
        "brand": normalize_visible_text(row["brand"]),
        "manufacturer": normalize_visible_text(row["manufacturer"]),
        "category_name": normalize_visible_text(row["category_name"]),
        "subcategory_name": normalize_visible_text(row["subcategory_name"]),
        "package_unit": normalize_visible_text(row["package_unit"]),
        "unit_type": normalize_visible_text(row["unit_type"]),
        "description": normalize_visible_text(row["description"]),
        "source": normalize_visible_text(row["source"]).lower(),
        "verification_status": normalize_visible_text(row["verification_status"]).lower(),
        "source_reference": normalize_visible_text(row["source_reference"]),
        "image_source_key": normalize_visible_text(row["image_source_key"]),
        "image_license": normalize_visible_text(row["image_license"]).lower(),
        "image_attribution": normalize_visible_text(row["image_attribution"]),
        "source_row": row_number,
    }

    normalized["barcode_normalized"] = _validate_barcode(
        normalized["primary_barcode"],
        normalized["barcode_type"],
        file_name,
        row_number,
        "primary_barcode",
        issues,
    )
    normalized["package_size"] = _issue_for_decimal(
        row["package_size"],
        file_name,
        row_number,
        "package_size",
        issues,
        required=False,
        minimum_exclusive=Decimal("0"),
    )
    normalized["confidence_score"] = _issue_for_decimal(
        row["confidence_score"],
        file_name,
        row_number,
        "confidence_score",
        issues,
        required=True,
        maximum_inclusive=Decimal("1"),
    )

    normalized["category_name"] = _validate_vocabulary(
        normalized["category_name"], vocab["categories"], file_name, row_number, "category_name", issues
    )
    normalized["unit_type"] = _validate_vocabulary(
        normalized["unit_type"], vocab["unit_types"], file_name, row_number, "unit_type", issues
    )
    normalized["source"] = _validate_vocabulary(
        normalized["source"], vocab["sources"], file_name, row_number, "source", issues
    )
    normalized["verification_status"] = _validate_vocabulary(
        normalized["verification_status"],
        vocab["verification_statuses"],
        file_name,
        row_number,
        "verification_status",
        issues,
    )
    normalized["barcode_type"] = _validate_vocabulary(
        normalized["barcode_type"],
        vocab["barcode_types"],
        file_name,
        row_number,
        "barcode_type",
        issues,
    )
    if normalized["package_unit"]:
        normalized["package_unit"] = _validate_vocabulary(
            normalized["package_unit"],
            vocab["package_units"],
            file_name,
            row_number,
            "package_unit",
            issues,
        )

    has_size = bool(normalized["package_size"])
    has_unit = bool(normalized["package_unit"])
    if has_size != has_unit:
        issues.append(
            Issue(
                "error",
                "invalid_package_pair",
                file_name,
                row_number,
                "package_size",
                "package_size and package_unit must be provided together",
            )
        )
    if normalized["unit_type"] in vocab["quantified_unit_types"] and not (has_size and has_unit):
        issues.append(
            Issue(
                "error",
                "missing_quantified_package",
                file_name,
                row_number,
                "package_size",
                "This unit_type requires package_size and package_unit",
            )
        )

    if normalized["image_license"]:
        normalized["image_license"] = _validate_vocabulary(
            normalized["image_license"],
            vocab["image_licenses"],
            file_name,
            row_number,
            "image_license",
            issues,
        )
    if normalized["image_source_key"] and not normalized["image_license"]:
        issues.append(
            Issue(
                "error",
                "image_license_required",
                file_name,
                row_number,
                "image_license",
                "image_license is required when image_source_key is present",
            )
        )
    if (
        normalized["image_source_key"]
        and normalized["image_license"] in vocab["image_attribution_required_for"]
        and not normalized["image_attribution"]
    ):
        issues.append(
            Issue(
                "error",
                "image_attribution_required",
                file_name,
                row_number,
                "image_attribution",
                "Attribution is required for this image license/source",
            )
        )
    if not normalized["image_source_key"] and (
        normalized["image_license"] or normalized["image_attribution"]
    ):
        issues.append(
            Issue(
                "warning",
                "image_provenance_without_image",
                file_name,
                row_number,
                "image_source_key",
                "Image provenance is present but image_source_key is empty",
            )
        )

    hash_input = {
        key: value
        for key, value in normalized.items()
        if key not in {"source_row", "barcode_normalized"}
    }
    hash_input["primary_barcode"] = normalized["barcode_normalized"]
    normalized["record_hash"] = record_hash(hash_input)
    return normalized


def _parse_bool(value: str) -> bool | None:
    normalized = normalize_visible_text(value).casefold()
    if normalized == "true":
        return True
    if normalized == "false":
        return False
    return None


def _normalize_barcode_row(
    row: dict[str, str], vocab: dict[str, Any], file_name: str, issues: list[Issue]
) -> dict[str, Any]:
    row_number = int(row["__row_number__"])
    _add_required_issues(row, REQUIRED_BARCODE_FIELDS, file_name, row_number, issues)
    _validate_secret_values(row, file_name, row_number, issues)
    normalized: dict[str, Any] = {
        "barcode_id": _issue_for_uuid(row["barcode_id"], file_name, row_number, "barcode_id", issues),
        "master_product_id": _issue_for_uuid(
            row["master_product_id"], file_name, row_number, "master_product_id", issues
        ),
        "barcode": normalize_visible_text(row["barcode"]),
        "barcode_type": normalize_visible_text(row["barcode_type"]).lower(),
        "source": normalize_visible_text(row["source"]).lower(),
        "source_reference": normalize_visible_text(row["source_reference"]),
        "source_row": row_number,
    }
    parsed_primary = _parse_bool(row["is_primary"])
    if parsed_primary is None:
        issues.append(
            Issue(
                "error",
                "invalid_boolean",
                file_name,
                row_number,
                "is_primary",
                "is_primary must be exactly true or false",
            )
        )
    normalized["is_primary"] = parsed_primary
    normalized["barcode_type"] = _validate_vocabulary(
        normalized["barcode_type"],
        vocab["barcode_types"],
        file_name,
        row_number,
        "barcode_type",
        issues,
    )
    normalized["barcode_normalized"] = _validate_barcode(
        normalized["barcode"],
        normalized["barcode_type"],
        file_name,
        row_number,
        "barcode",
        issues,
    )
    normalized["source"] = _validate_vocabulary(
        normalized["source"], vocab["sources"], file_name, row_number, "source", issues
    )
    normalized["confidence_score"] = _issue_for_decimal(
        row["confidence_score"],
        file_name,
        row_number,
        "confidence_score",
        issues,
        required=True,
        maximum_inclusive=Decimal("1"),
    )
    hash_input = {
        key: value
        for key, value in normalized.items()
        if key not in {"source_row", "barcode_normalized"}
    }
    hash_input["barcode"] = normalized["barcode_normalized"]
    normalized["record_hash"] = record_hash(hash_input)
    return normalized


def _issue_sort_key(issue: Issue) -> tuple[Any, ...]:
    return (issue.file, issue.row or 0, issue.field or "", issue.code, issue.message)


def _semantic_key(master: dict[str, Any]) -> tuple[str, ...]:
    return (
        normalize_semantic_text(master["name"]),
        normalize_semantic_text(master["brand"]),
        master["package_size"],
        normalize_semantic_text(master["package_unit"]),
        normalize_semantic_text(master["unit_type"]),
    )


def _near_duplicate(left: dict[str, Any], right: dict[str, Any], threshold: Decimal) -> bool:
    if left["master_product_id"] == right["master_product_id"]:
        return False
    comparable_left = _semantic_key(left)[1:]
    comparable_right = _semantic_key(right)[1:]
    if comparable_left != comparable_right:
        return False
    left_name = normalize_semantic_text(left["name"])
    right_name = normalize_semantic_text(right["name"])
    if not left_name or not right_name or left_name == right_name:
        return False
    ratio = Decimal(str(SequenceMatcher(None, left_name, right_name).ratio()))
    return left_name in right_name or right_name in left_name or ratio >= threshold


def validate_dataset(
    *,
    masters_path: Path = DEFAULT_MASTERS,
    barcodes_path: Path = DEFAULT_BARCODES,
    manifest_path: Path = DEFAULT_MANIFEST,
    vocabularies_path: Path = DEFAULT_CONFIG,
) -> dict[str, Any]:
    manifest = _load_manifest(manifest_path)
    vocab = _load_vocabularies(vocabularies_path)
    master_rows, issues = _read_csv(masters_path, MASTER_HEADERS)
    barcode_rows, barcode_header_issues = _read_csv(barcodes_path, BARCODE_HEADERS)
    issues.extend(barcode_header_issues)

    masters = [_normalize_master(row, vocab, masters_path.name, issues) for row in master_rows]
    barcodes = [_normalize_barcode_row(row, vocab, barcodes_path.name, issues) for row in barcode_rows]
    semantic_candidates: list[dict[str, Any]] = []
    barcode_conflicts: list[dict[str, Any]] = []

    master_by_id: dict[str, dict[str, Any]] = {}
    for master in masters:
        master_id = master["master_product_id"]
        if master_id in master_by_id and master_id:
            issues.append(
                Issue(
                    "error",
                    "duplicate_master_product_id",
                    masters_path.name,
                    master["source_row"],
                    "master_product_id",
                    "master_product_id appears more than once",
                    {"master_product_id": master_id},
                )
            )
        elif master_id:
            master_by_id[master_id] = master

    barcode_ids: dict[str, dict[str, Any]] = {}
    barcode_owners: dict[str, list[dict[str, Any]]] = {}
    barcodes_by_master: dict[str, list[dict[str, Any]]] = {}
    for barcode in barcodes:
        barcode_id = barcode["barcode_id"]
        master_id = barcode["master_product_id"]
        if barcode_id in barcode_ids and barcode_id:
            issues.append(
                Issue(
                    "error",
                    "duplicate_barcode_id",
                    barcodes_path.name,
                    barcode["source_row"],
                    "barcode_id",
                    "barcode_id appears more than once",
                    {"barcode_id": barcode_id},
                )
            )
        elif barcode_id:
            barcode_ids[barcode_id] = barcode
        if master_id and master_id not in master_by_id:
            issues.append(
                Issue(
                    "error",
                    "unknown_master_product_id",
                    barcodes_path.name,
                    barcode["source_row"],
                    "master_product_id",
                    "Barcode references a master_product_id absent from the seed",
                    {"master_product_id": master_id},
                )
            )
        barcode_owners.setdefault(barcode["barcode_normalized"], []).append(barcode)
        barcodes_by_master.setdefault(master_id, []).append(barcode)
        if barcode["is_primary"] is False:
            issues.append(
                Issue(
                    "warning",
                    "alternate_barcode_review_required",
                    barcodes_path.name,
                    barcode["source_row"],
                    "barcode",
                    "Alternate barcode must be manually confirmed as the same presentation",
                    {"master_product_id": master_id, "barcode": barcode["barcode_normalized"]},
                )
            )

    for normalized_code, owners in sorted(barcode_owners.items()):
        if not normalized_code or len(owners) < 2:
            continue
        master_ids = sorted({owner["master_product_id"] for owner in owners})
        if len(master_ids) > 1:
            conflict = {"barcode_normalized": normalized_code, "master_product_ids": master_ids}
            barcode_conflicts.append(conflict)
            for owner in owners:
                issues.append(
                    Issue(
                        "error",
                        "barcode_conflict_across_masters",
                        barcodes_path.name,
                        owner["source_row"],
                        "barcode",
                        "The same normalized barcode is assigned to different masters",
                        conflict,
                    )
                )
        else:
            issues.append(
                Issue(
                    "warning",
                    "duplicate_barcode_same_master",
                    barcodes_path.name,
                    owners[-1]["source_row"],
                    "barcode",
                    "Repeated barcode for the same master is an idempotent duplicate/no-op candidate",
                    {"barcode_normalized": normalized_code, "master_product_id": master_ids[0]},
                )
            )

    for master in masters:
        master_id = master["master_product_id"]
        primary_rows = [row for row in barcodes_by_master.get(master_id, []) if row["is_primary"] is True]
        matching_primary = [
            row for row in primary_rows if row["barcode_normalized"] == master["barcode_normalized"]
        ]
        if len(primary_rows) != 1 or len(matching_primary) != 1:
            issues.append(
                Issue(
                    "error",
                    "primary_barcode_contract_violation",
                    masters_path.name,
                    master["source_row"],
                    "primary_barcode",
                    "Each master must have exactly one matching is_primary=true row in master_catalog_barcodes.csv",
                    {
                        "master_product_id": master_id,
                        "primary_rows": len(primary_rows),
                        "matching_primary_rows": len(matching_primary),
                    },
                )
            )

    for index, left in enumerate(masters):
        for right in masters[index + 1 :]:
            if _semantic_key(left) == _semantic_key(right):
                candidate = {
                    "classification": "exact",
                    "master_product_ids": [left["master_product_id"], right["master_product_id"]],
                    "semantic_key": list(_semantic_key(left)),
                }
                semantic_candidates.append(candidate)
                for master in (left, right):
                    issues.append(
                        Issue(
                            "error",
                            "exact_semantic_duplicate",
                            masters_path.name,
                            master["source_row"],
                            "name",
                            "Exact semantic duplicate requires curator review",
                            candidate,
                        )
                    )
            elif _near_duplicate(left, right, Decimal(str(vocab.get("near_duplicate_threshold", "0.88")))):
                candidate = {
                    "classification": "near",
                    "master_product_ids": [left["master_product_id"], right["master_product_id"]],
                    "names": [left["name"], right["name"]],
                }
                semantic_candidates.append(candidate)
                issues.append(
                    Issue(
                        "warning",
                        "near_semantic_duplicate",
                        masters_path.name,
                        right["source_row"],
                        "name",
                        "Near semantic duplicate requires curator review",
                        candidate,
                    )
                )

    errors = sorted((issue for issue in issues if issue.severity == "error"), key=_issue_sort_key)
    warnings = sorted((issue for issue in issues if issue.severity == "warning"), key=_issue_sort_key)
    invalid_row_keys = {(issue.file, issue.row) for issue in errors if issue.row and issue.row > 1}
    total_rows = len(masters) + len(barcodes)

    image_rows = [master for master in masters if master["image_source_key"]]
    image_missing_license = [
        master["master_product_id"] for master in image_rows if not master["image_license"]
    ]
    image_missing_attribution = [
        master["master_product_id"]
        for master in image_rows
        if master["image_license"] in vocab["image_attribution_required_for"]
        and not master["image_attribution"]
    ]

    report = {
        "tool_version": TOOL_VERSION,
        "schema_version": SCHEMA_VERSION,
        "dataset_version": normalize_visible_text(manifest["dataset_version"]),
        "dataset_description": normalize_visible_text(manifest.get("description")),
        "valid": not errors,
        "total_rows": total_rows,
        "master_rows": len(masters),
        "barcode_rows": len(barcodes),
        "valid_rows": total_rows - len(invalid_row_keys),
        "invalid_rows": len(invalid_row_keys),
        "blocking_error_count": len(errors),
        "warning_count": len(warnings),
        "blocking_errors": [issue.to_dict() for issue in errors],
        "warnings": [issue.to_dict() for issue in warnings],
        "semantic_duplicate_candidates": sorted(
            semantic_candidates, key=lambda item: stable_json(item)
        ),
        "barcode_conflicts": sorted(barcode_conflicts, key=lambda item: stable_json(item)),
        "normalized_preview": {"masters": masters, "barcodes": barcodes},
        "record_hashes": {
            "masters": [
                {"master_product_id": row["master_product_id"], "record_hash": row["record_hash"]}
                for row in masters
            ],
            "barcodes": [
                {"barcode_id": row["barcode_id"], "record_hash": row["record_hash"]}
                for row in barcodes
            ],
        },
        "image_provenance_status": {
            "rows_with_image": len(image_rows),
            "documented_rows": len(image_rows)
            - len(set(image_missing_license) | set(image_missing_attribution)),
            "missing_license_master_product_ids": image_missing_license,
            "missing_attribution_master_product_ids": image_missing_attribution,
        },
        "database_access": False,
    }
    return report


def report_json(report: dict[str, Any]) -> str:
    return json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def human_report(report: dict[str, Any]) -> str:
    status = "VALID" if report["valid"] else "INVALID"
    lines = [
        f"Catalog dataset {report['dataset_version']}: {status}",
        f"Rows: {report['total_rows']} (masters={report['master_rows']}, barcodes={report['barcode_rows']})",
        f"Valid rows: {report['valid_rows']}; invalid rows: {report['invalid_rows']}",
        f"Blocking errors: {report['blocking_error_count']}; warnings: {report['warning_count']}",
        f"Semantic duplicate candidates: {len(report['semantic_duplicate_candidates'])}",
        f"Barcode conflicts: {len(report['barcode_conflicts'])}",
        f"Images documented: {report['image_provenance_status']['documented_rows']}/"
        f"{report['image_provenance_status']['rows_with_image']}",
        "Database access: none",
    ]
    for issue in report["blocking_errors"] + report["warnings"]:
        location = f"{issue['file']}:{issue.get('row', '-')}"
        if issue.get("field"):
            location += f" [{issue['field']}]"
        lines.append(f"{issue['severity'].upper()} {issue['code']} {location}: {issue['message']}")
    return "\n".join(lines)


def _write_csv_temp(path: Path, headers: Sequence[str], rows: Sequence[dict[str, str]]) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", newline="", delete=False, dir=path.parent, prefix=f".{path.name}.", suffix=".tmp"
    )
    temp_path = Path(handle.name)
    try:
        with handle:
            writer = csv.DictWriter(handle, fieldnames=headers, lineterminator="\n")
            writer.writeheader()
            for row in rows:
                writer.writerow({header: row.get(header, "") for header in headers})
        return temp_path
    except Exception:
        temp_path.unlink(missing_ok=True)
        raise


def allocate_ids(*, masters_path: Path, barcodes_path: Path) -> dict[str, int]:
    masters, master_issues = _read_csv(masters_path, MASTER_HEADERS)
    barcodes, barcode_issues = _read_csv(barcodes_path, BARCODE_HEADERS)
    header_errors = [
        issue for issue in master_issues + barcode_issues if issue.severity == "error"
    ]
    if header_errors:
        raise CatalogToolError("Cannot allocate IDs until both CSV headers match the contract")

    allocated_master_ids = 0
    allocated_barcode_ids = 0
    linked_barcode_master_ids = 0
    primary_to_master: dict[str, str] = {}
    ambiguous_primary_codes: set[str] = set()

    for master in masters:
        current = normalize_visible_text(master["master_product_id"])
        if not current:
            master["master_product_id"] = str(uuid.uuid4())
            allocated_master_ids += 1
        normalized_primary = normalize_barcode(master["primary_barcode"])
        if normalized_primary:
            if normalized_primary in primary_to_master:
                ambiguous_primary_codes.add(normalized_primary)
            else:
                primary_to_master[normalized_primary] = master["master_product_id"]

    for barcode in barcodes:
        if not normalize_visible_text(barcode["barcode_id"]):
            barcode["barcode_id"] = str(uuid.uuid4())
            allocated_barcode_ids += 1
        if not normalize_visible_text(barcode["master_product_id"]):
            normalized = normalize_barcode(barcode["barcode"])
            if normalized and normalized not in ambiguous_primary_codes and normalized in primary_to_master:
                barcode["master_product_id"] = primary_to_master[normalized]
                linked_barcode_master_ids += 1

    master_temp = _write_csv_temp(masters_path, MASTER_HEADERS, masters)
    barcode_temp = _write_csv_temp(barcodes_path, BARCODE_HEADERS, barcodes)
    try:
        os.replace(master_temp, masters_path)
        os.replace(barcode_temp, barcodes_path)
    finally:
        master_temp.unlink(missing_ok=True)
        barcode_temp.unlink(missing_ok=True)

    return {
        "allocated_master_product_ids": allocated_master_ids,
        "allocated_barcode_ids": allocated_barcode_ids,
        "linked_barcode_master_ids": linked_barcode_master_ids,
    }


def _primary_sync_conflict(
    code: str,
    master: dict[str, Any] | None,
    *,
    message: str,
    details: dict[str, Any] | None = None,
) -> dict[str, Any]:
    conflict: dict[str, Any] = {
        "code": code,
        "message": message,
    }
    if master is not None:
        conflict.update(
            {
                "seed_line": master["source_row"],
                "master_product_id": master["master_product_id"],
                "barcode": master["barcode_normalized"],
            }
        )
    if details:
        conflict["details"] = details
    return conflict


def plan_primary_barcode_sync(
    *,
    masters_path: Path = DEFAULT_MASTERS,
    barcodes_path: Path = DEFAULT_BARCODES,
    vocabularies_path: Path = DEFAULT_CONFIG,
) -> dict[str, Any]:
    """Plan primary relations without writing either CSV."""
    vocab = _load_vocabularies(vocabularies_path)
    master_rows, master_header_issues = _read_csv(masters_path, MASTER_HEADERS)
    barcode_rows, barcode_header_issues = _read_csv(barcodes_path, BARCODE_HEADERS)
    input_issues = [*master_header_issues, *barcode_header_issues]
    masters = [
        _normalize_master(row, vocab, masters_path.name, input_issues)
        for row in master_rows
    ]
    barcodes = [
        _normalize_barcode_row(row, vocab, barcodes_path.name, input_issues)
        for row in barcode_rows
    ]

    invalid_master_rows = {
        issue.row
        for issue in input_issues
        if issue.severity == "error"
        and issue.file == masters_path.name
        and issue.row is not None
        and issue.row > 1
    }
    valid_masters = [master for master in masters if master["source_row"] not in invalid_master_rows]
    global_input_issues = [
        issue
        for issue in input_issues
        if issue.severity == "error"
        and (
            issue.row in (None, 1)
            or issue.file == barcodes_path.name
        )
    ]

    conflicts: list[dict[str, Any]] = []
    master_by_id: dict[str, dict[str, Any]] = {}
    seed_code_owners: dict[str, list[dict[str, Any]]] = {}
    for master in valid_masters:
        master_id = master["master_product_id"]
        if master_id in master_by_id and master_id:
            conflicts.append(
                _primary_sync_conflict(
                    "duplicate_master_product_id",
                    master,
                    message="master_product_id appears more than once in the seed",
                    details={"first_seed_line": master_by_id[master_id]["source_row"]},
                )
            )
        elif master_id:
            master_by_id[master_id] = master
        seed_code_owners.setdefault(master["barcode_normalized"], []).append(master)

    for code, owners in sorted(seed_code_owners.items()):
        owner_ids = sorted({row["master_product_id"] for row in owners if row["master_product_id"]})
        if code and len(owner_ids) > 1:
            for owner in owners:
                conflicts.append(
                    _primary_sync_conflict(
                        "cross_master_collision",
                        owner,
                        message="Seed primary barcode is assigned to more than one master",
                        details={"master_product_ids": owner_ids},
                    )
                )

    barcodes_by_master: dict[str, list[dict[str, Any]]] = {}
    barcodes_by_code: dict[str, list[dict[str, Any]]] = {}
    raw_barcode_by_id: dict[str, dict[str, str]] = {}
    for raw, barcode in zip(barcode_rows, barcodes):
        barcodes_by_master.setdefault(barcode["master_product_id"], []).append(barcode)
        barcodes_by_code.setdefault(barcode["barcode_normalized"], []).append(barcode)
        if barcode["barcode_id"]:
            raw_barcode_by_id[barcode["barcode_id"]] = raw

    already_correct: list[dict[str, Any]] = []
    inserts: list[dict[str, str]] = []
    promotions: list[dict[str, Any]] = []
    conflicted_master_ids = {
        conflict.get("master_product_id") for conflict in conflicts if conflict.get("master_product_id")
    }

    for master in valid_masters:
        master_id = master["master_product_id"]
        code = master["barcode_normalized"]
        if not master_id or master_id in conflicted_master_ids:
            continue

        foreign_owners = sorted(
            {
                row["master_product_id"]
                for row in barcodes_by_code.get(code, [])
                if row["master_product_id"] and row["master_product_id"] != master_id
            }
        )
        if foreign_owners:
            conflicts.append(
                _primary_sync_conflict(
                    "cross_master_collision",
                    master,
                    message="Seed primary barcode is already associated with another master",
                    details={"other_master_product_ids": foreign_owners},
                )
            )
            continue

        master_rows_for_barcode = barcodes_by_master.get(master_id, [])
        primary_rows = [row for row in master_rows_for_barcode if row["is_primary"] is True]
        if len(primary_rows) > 1:
            conflicts.append(
                _primary_sync_conflict(
                    "multiple_primary",
                    master,
                    message="Master already has more than one primary barcode row",
                    details={"barcode_ids": sorted(row["barcode_id"] for row in primary_rows)},
                )
            )
            continue
        if len(primary_rows) == 1:
            primary = primary_rows[0]
            if primary["barcode_normalized"] != code:
                conflicts.append(
                    _primary_sync_conflict(
                        "contradictory_primary",
                        master,
                        message="Existing primary barcode contradicts the seed primary barcode",
                        details={
                            "existing_barcode_id": primary["barcode_id"],
                            "existing_barcode": primary["barcode_normalized"],
                        },
                    )
                )
            else:
                already_correct.append(
                    {
                        "seed_line": master["source_row"],
                        "master_product_id": master_id,
                        "barcode_id": primary["barcode_id"],
                        "barcode": code,
                    }
                )
            continue

        same_aliases = [
            row for row in master_rows_for_barcode if row["barcode_normalized"] == code
        ]
        if len(same_aliases) > 1:
            conflicts.append(
                _primary_sync_conflict(
                    "ambiguous_alias",
                    master,
                    message="More than one existing alias could be promoted to primary",
                    details={"barcode_ids": sorted(row["barcode_id"] for row in same_aliases)},
                )
            )
            continue
        if len(same_aliases) == 1:
            alias = same_aliases[0]
            promotions.append(
                {
                    "seed_line": master["source_row"],
                    "master_product_id": master_id,
                    "barcode_id": alias["barcode_id"],
                    "barcode": code,
                }
            )
            continue

        inserts.append(
            {
                "barcode_id": str(uuid.uuid4()),
                "master_product_id": master_id,
                "barcode": code,
                "barcode_type": master["barcode_type"],
                "is_primary": "true",
                "source": master["source"],
                "confidence_score": master["confidence_score"],
                "source_reference": master["source_reference"],
            }
        )

    sorted_issues = sorted(
        (issue for issue in input_issues if issue.severity == "error"), key=_issue_sort_key
    )
    conflicts.sort(
        key=lambda item: (
            item.get("seed_line", 0),
            item["code"],
            item.get("master_product_id", ""),
        )
    )
    input_error_count = len(sorted_issues)
    return {
        "operation": "sync-primary-barcodes",
        "masters_total": len(masters),
        "masters_valid": len(valid_masters),
        "masters_skipped_invalid": len(masters) - len(valid_masters),
        "barcodes_total_before": len(barcodes),
        "already_correct": len(already_correct),
        "would_insert": len(inserts),
        "would_promote": len(promotions),
        "conflict_count": len(conflicts),
        "input_error_count": input_error_count,
        "blocking_input_error_count": len(global_input_issues),
        "cross_master_collisions": sum(
            conflict["code"] == "cross_master_collision" for conflict in conflicts
        ),
        "multiple_primary": sum(conflict["code"] == "multiple_primary" for conflict in conflicts),
        "contradictory_primary": sum(
            conflict["code"] == "contradictory_primary" for conflict in conflicts
        ),
        "ambiguous_alias": sum(conflict["code"] == "ambiguous_alias" for conflict in conflicts),
        "can_apply": not conflicts and not global_input_issues,
        "correct_rows": already_correct,
        "inserts": inserts,
        "promotions": promotions,
        "conflicts": conflicts,
        "input_errors": [issue.to_dict() for issue in sorted_issues],
        "_raw_barcodes": barcode_rows,
        "_raw_barcode_by_id": raw_barcode_by_id,
    }


def primary_barcode_sync_report_json(report: dict[str, Any]) -> str:
    public_report = {key: value for key, value in report.items() if not key.startswith("_")}
    return json.dumps(public_report, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def primary_barcode_sync_human_report(report: dict[str, Any]) -> str:
    lines = [
        f"Primary barcode sync: {report['status'].upper()}",
        f"Masters: {report['masters_total']} (valid={report['masters_valid']}, "
        f"skipped_invalid={report['masters_skipped_invalid']}); "
        f"existing barcode rows: {report['barcodes_total_before']}",
        f"Already correct: {report['already_correct']}",
        f"Would insert: {report['would_insert']}; would promote: {report['would_promote']}",
        f"Conflicts: {report['conflict_count']}; input errors: {report['input_error_count']} "
        f"(globally blocking={report['blocking_input_error_count']})",
        f"Cross-master: {report['cross_master_collisions']}; multiple primary: {report['multiple_primary']}; "
        f"contradictory primary: {report['contradictory_primary']}; ambiguous alias: {report['ambiguous_alias']}",
        f"Wrote barcodes CSV: {str(report['wrote_barcodes_csv']).lower()}",
    ]
    if report.get("backup_path"):
        lines.append(f"Backup: {report['backup_path']}")
    for conflict in report["conflicts"]:
        lines.append(
            f"CONFLICT {conflict['code']} seed_line={conflict.get('seed_line', '-')} "
            f"master={conflict.get('master_product_id', '-')} barcode={conflict.get('barcode', '-')}: "
            f"{conflict['message']}"
        )
    for issue in report["input_errors"]:
        lines.append(
            f"ERROR {issue['code']} {issue['file']}:{issue.get('row', '-')} "
            f"[{issue.get('field', '-')}] {issue['message']}"
        )
    return "\n".join(lines)


def sync_primary_barcodes(
    *,
    masters_path: Path = DEFAULT_MASTERS,
    barcodes_path: Path = DEFAULT_BARCODES,
    manifest_path: Path = DEFAULT_MANIFEST,
    vocabularies_path: Path = DEFAULT_CONFIG,
    backup_dir: Path = DEFAULT_BACKUP_DIR,
    dry_run: bool = False,
) -> dict[str, Any]:
    plan = plan_primary_barcode_sync(
        masters_path=masters_path,
        barcodes_path=barcodes_path,
        vocabularies_path=vocabularies_path,
    )
    plan.update(
        {
            "status": "blocked" if not plan["can_apply"] else "dry_run" if dry_run else "planned",
            "wrote_barcodes_csv": False,
            "backup_path": None,
        }
    )
    if not plan["can_apply"] or dry_run:
        return plan

    if plan["would_insert"] == 0 and plan["would_promote"] == 0:
        plan["status"] = "no_op"
        return plan

    output_rows = [dict(row) for row in plan["_raw_barcodes"]]
    promotion_ids = {row["barcode_id"] for row in plan["promotions"]}
    for row in output_rows:
        if normalize_visible_text(row.get("barcode_id")).lower() in promotion_ids:
            row["is_primary"] = "true"
    output_rows.extend(plan["inserts"])

    candidate = _write_csv_temp(barcodes_path, BARCODE_HEADERS, output_rows)
    try:
        baseline_validation = validate_dataset(
            masters_path=masters_path,
            barcodes_path=barcodes_path,
            manifest_path=manifest_path,
            vocabularies_path=vocabularies_path,
        )
        validation = validate_dataset(
            masters_path=masters_path,
            barcodes_path=candidate,
            manifest_path=manifest_path,
            vocabularies_path=vocabularies_path,
        )
        def issue_signature(issue: dict[str, Any]) -> tuple[Any, ...]:
            return (
                issue.get("code"),
                issue.get("row"),
                issue.get("field"),
                issue.get("message"),
                stable_json(issue.get("details", {})),
            )

        baseline_error_signatures = {
            issue_signature(issue) for issue in baseline_validation["blocking_errors"]
        }
        unexpected_errors = [
            issue
            for issue in validation["blocking_errors"]
            if issue_signature(issue) not in baseline_error_signatures
        ]
        valid_master_ids = {
            row["master_product_id"]
            for row in plan["correct_rows"] + plan["inserts"] + plan["promotions"]
        }
        unresolved_valid_primaries = [
            issue
            for issue in validation["blocking_errors"]
            if issue["code"] == "primary_barcode_contract_violation"
            and issue.get("details", {}).get("master_product_id") in valid_master_ids
        ]
        if unexpected_errors or unresolved_valid_primaries:
            plan["status"] = "blocked"
            plan["can_apply"] = False
            plan["post_validation_errors"] = unexpected_errors + unresolved_valid_primaries
            return plan

        backup_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        original_hash = hashlib.sha256(barcodes_path.read_bytes()).hexdigest()[:12]
        backup_path = backup_dir / f"master_catalog_barcodes.{timestamp}.{original_hash}.csv"
        shutil.copy2(barcodes_path, backup_path)
        os.replace(candidate, barcodes_path)
        plan.update(
            {
                "status": "applied",
                "wrote_barcodes_csv": True,
                "backup_path": str(backup_path),
                "barcodes_total_after": len(output_rows),
            }
        )
        return plan
    finally:
        candidate.unlink(missing_ok=True)


def plan_invalid_barcode_master_prune(
    *,
    masters_path: Path = DEFAULT_MASTERS,
    barcodes_path: Path = DEFAULT_BARCODES,
    rejected_report_path: Path = DEFAULT_REJECTED_INVALID_BARCODE_REPORT,
    vocabularies_path: Path = DEFAULT_CONFIG,
    expected_count: int = 56,
) -> dict[str, Any]:
    """Identify only validator-confirmed invalid-barcode masters for pruning."""
    if expected_count <= 0:
        raise CatalogToolError("expected_count must be greater than zero")
    resolved_paths = {
        masters_path.resolve(),
        barcodes_path.resolve(),
        rejected_report_path.resolve(),
    }
    if len(resolved_paths) != 3:
        raise CatalogToolError("masters, barcodes, and rejected report paths must be distinct")

    vocab = _load_vocabularies(vocabularies_path)
    master_rows, master_header_issues = _read_csv(masters_path, MASTER_HEADERS)
    barcode_rows, barcode_header_issues = _read_csv(barcodes_path, BARCODE_HEADERS)
    issues = [*master_header_issues, *barcode_header_issues]
    [_normalize_master(row, vocab, masters_path.name, issues) for row in master_rows]

    invalid_barcode_rows = sorted(
        {
            issue.row
            for issue in issues
            if issue.severity == "error"
            and issue.code == "invalid_barcode"
            and issue.file == masters_path.name
            and issue.field == "primary_barcode"
            and issue.row is not None
        }
    )
    raw_master_by_row = {int(row["__row_number__"]): row for row in master_rows}
    target_rows = [raw_master_by_row[row_number] for row_number in invalid_barcode_rows]
    target_ids = [normalize_visible_text(row["master_product_id"]).lower() for row in target_rows]
    target_id_set = set(target_ids)
    related_rows = [
        row
        for row in barcode_rows
        if normalize_visible_text(row["master_product_id"]).lower() in target_id_set
    ]
    retained_rows = [
        row for row in master_rows if int(row["__row_number__"]) not in invalid_barcode_rows
    ]
    audit_rows = [
        {
            **{header: row.get(header, "") for header in MASTER_HEADERS},
            "rejection_reason": "invalid_primary_barcode",
        }
        for row in target_rows
    ]

    blockers: list[dict[str, Any]] = []
    header_errors = [
        issue.to_dict()
        for issue in issues
        if issue.severity == "error" and issue.row in (None, 1)
    ]
    blockers.extend(header_errors)
    if invalid_barcode_rows and len(target_rows) != expected_count:
        blockers.append(
            {
                "code": "unexpected_invalid_barcode_master_count",
                "message": f"Expected {expected_count} invalid-barcode masters, found {len(target_rows)}",
            }
        )
    if invalid_barcode_rows and (
        len(target_id_set) != len(target_rows) or any(not is_valid_uuid(value) for value in target_ids)
    ):
        blockers.append(
            {
                "code": "invalid_or_duplicate_target_master_id",
                "message": "Every prune target must have a unique valid master_product_id",
            }
        )
    if related_rows:
        blockers.append(
            {
                "code": "target_has_relational_barcode",
                "message": "At least one invalid-barcode master has a relational barcode row",
                "master_product_ids": sorted(
                    {
                        normalize_visible_text(row["master_product_id"]).lower()
                        for row in related_rows
                    }
                ),
            }
        )

    existing_audit_rows: list[dict[str, str]] = []
    audit_matches = False
    if rejected_report_path.exists():
        existing_audit_rows, audit_issues = _read_csv(
            rejected_report_path, REJECTED_INVALID_BARCODE_HEADERS
        )
        audit_matches = not audit_issues and [
            {header: row.get(header, "") for header in REJECTED_INVALID_BARCODE_HEADERS}
            for row in existing_audit_rows
        ] == audit_rows
        if target_rows and not audit_matches:
            blockers.append(
                {
                    "code": "existing_rejected_report_mismatch",
                    "message": "Existing rejected-row report does not match the current prune targets",
                }
            )

    already_pruned = not target_rows
    if already_pruned:
        audit_ids = [
            normalize_visible_text(row["master_product_id"]).lower()
            for row in existing_audit_rows
        ]
        audit_id_set = set(audit_ids)
        current_master_ids = {
            normalize_visible_text(row["master_product_id"]).lower() for row in master_rows
        }
        audit_relations = [
            row
            for row in barcode_rows
            if normalize_visible_text(row["master_product_id"]).lower() in audit_id_set
        ]
        audit_matches = (
            len(existing_audit_rows) == expected_count
            and len(audit_id_set) == expected_count
            and all(
                row.get("rejection_reason") == "invalid_primary_barcode"
                for row in existing_audit_rows
            )
            and not (audit_id_set & current_master_ids)
            and not audit_relations
        )
        if not audit_matches:
            blockers.append(
                {
                    "code": "missing_or_invalid_rejected_report",
                    "message": "No current targets exist and the prior rejected-row audit is not valid",
                }
            )

    target_set_hash = hashlib.sha256("\n".join(sorted(target_id_set)).encode("utf-8")).hexdigest()
    return {
        "operation": "prune-invalid-barcode-masters",
        "status": "no_op" if already_pruned and not blockers else "planned",
        "masters_before": len(master_rows),
        "invalid_barcode_masters": len(target_rows),
        "expected_invalid_barcode_masters": expected_count,
        "related_barcode_rows": len(related_rows),
        "masters_after": len(retained_rows),
        "target_master_ids": sorted(target_id_set),
        "target_id_set_sha256": target_set_hash,
        "blockers": blockers,
        "can_apply": not blockers,
        "already_pruned": already_pruned,
        "audit_matches": audit_matches,
        "_retained_rows": retained_rows,
        "_audit_rows": audit_rows,
    }


def invalid_barcode_prune_report_json(report: dict[str, Any]) -> str:
    public_report = {key: value for key, value in report.items() if not key.startswith("_")}
    return json.dumps(public_report, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def invalid_barcode_prune_human_report(report: dict[str, Any]) -> str:
    lines = [
        f"Invalid barcode master pruning: {report['status'].upper()}",
        f"Masters: {report['masters_before']} -> {report['masters_after']}",
        f"Invalid barcode targets: {report['invalid_barcode_masters']}",
        f"Related barcode rows: {report['related_barcode_rows']}",
        f"Wrote seed: {str(report['wrote_seed']).lower()}",
        f"Wrote rejected report: {str(report['wrote_rejected_report']).lower()}",
    ]
    if report.get("backup_path"):
        lines.append(f"Backup: {report['backup_path']}")
    for blocker in report["blockers"]:
        lines.append(f"BLOCKER {blocker['code']}: {blocker['message']}")
    return "\n".join(lines)


def prune_invalid_barcode_masters(
    *,
    masters_path: Path = DEFAULT_MASTERS,
    barcodes_path: Path = DEFAULT_BARCODES,
    rejected_report_path: Path = DEFAULT_REJECTED_INVALID_BARCODE_REPORT,
    manifest_path: Path = DEFAULT_MANIFEST,
    vocabularies_path: Path = DEFAULT_CONFIG,
    backup_dir: Path = DEFAULT_BACKUP_DIR,
    expected_count: int = 56,
    dry_run: bool = False,
) -> dict[str, Any]:
    plan = plan_invalid_barcode_master_prune(
        masters_path=masters_path,
        barcodes_path=barcodes_path,
        rejected_report_path=rejected_report_path,
        vocabularies_path=vocabularies_path,
        expected_count=expected_count,
    )
    plan.update(
        {
            "status": "blocked" if not plan["can_apply"] else plan["status"],
            "wrote_seed": False,
            "wrote_rejected_report": False,
            "backup_path": None,
            "rejected_report_path": str(rejected_report_path),
        }
    )
    if not plan["can_apply"] or plan["already_pruned"]:
        return plan
    if dry_run:
        plan["status"] = "dry_run"
        return plan

    candidate_seed = _write_csv_temp(masters_path, MASTER_HEADERS, plan["_retained_rows"])
    candidate_audit = _write_csv_temp(
        rejected_report_path, REJECTED_INVALID_BARCODE_HEADERS, plan["_audit_rows"]
    )
    try:
        baseline = validate_dataset(
            masters_path=masters_path,
            barcodes_path=barcodes_path,
            manifest_path=manifest_path,
            vocabularies_path=vocabularies_path,
        )
        candidate_validation = validate_dataset(
            masters_path=candidate_seed,
            barcodes_path=barcodes_path,
            manifest_path=manifest_path,
            vocabularies_path=vocabularies_path,
        )
        baseline_counts: dict[str, int] = {}
        candidate_counts: dict[str, int] = {}
        for issue in baseline["blocking_errors"]:
            baseline_counts[issue["code"]] = baseline_counts.get(issue["code"], 0) + 1
        for issue in candidate_validation["blocking_errors"]:
            candidate_counts[issue["code"]] = candidate_counts.get(issue["code"], 0) + 1
        new_error_codes = {
            code: count
            for code, count in candidate_counts.items()
            if count > baseline_counts.get(code, 0)
        }
        candidate_sync = plan_primary_barcode_sync(
            masters_path=candidate_seed,
            barcodes_path=barcodes_path,
            vocabularies_path=vocabularies_path,
        )
        if (
            new_error_codes
            or candidate_sync["masters_total"] != plan["masters_after"]
            or candidate_sync["masters_valid"] != plan["masters_after"]
            or candidate_sync["already_correct"] != plan["masters_after"]
            or candidate_sync["would_insert"] != 0
            or candidate_sync["would_promote"] != 0
            or candidate_sync["conflict_count"] != 0
            or candidate_sync["input_error_count"] != 0
        ):
            plan.update(
                {
                    "status": "blocked",
                    "can_apply": False,
                    "post_validation": {
                        "new_error_codes": new_error_codes,
                        "primary_sync": {
                            key: candidate_sync[key]
                            for key in (
                                "masters_total",
                                "masters_valid",
                                "already_correct",
                                "would_insert",
                                "would_promote",
                                "conflict_count",
                                "input_error_count",
                            )
                        },
                    },
                }
            )
            return plan

        backup_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        original_hash = hashlib.sha256(masters_path.read_bytes()).hexdigest()[:12]
        backup_path = backup_dir / f"master_catalog_seed.{timestamp}.{original_hash}.csv"
        shutil.copy2(masters_path, backup_path)

        rejected_report_path.parent.mkdir(parents=True, exist_ok=True)
        if not rejected_report_path.exists():
            os.replace(candidate_audit, rejected_report_path)
            plan["wrote_rejected_report"] = True
        os.replace(candidate_seed, masters_path)
        plan.update(
            {
                "status": "applied",
                "wrote_seed": True,
                "backup_path": str(backup_path),
                "seed_sha256_after": hashlib.sha256(masters_path.read_bytes()).hexdigest(),
            }
        )
        return plan
    finally:
        candidate_seed.unlink(missing_ok=True)
        candidate_audit.unlink(missing_ok=True)


def _exact_semantic_groups(validation: dict[str, Any]) -> list[dict[str, Any]]:
    grouped: dict[str, dict[str, Any]] = {}
    for candidate in validation["semantic_duplicate_candidates"]:
        if candidate["classification"] != "exact":
            continue
        semantic_key = candidate["semantic_key"]
        serialized_key = stable_json(semantic_key)
        group = grouped.setdefault(
            serialized_key,
            {
                "semantic_key": semantic_key,
                "duplicate_group_id": hashlib.sha256(
                    serialized_key.encode("utf-8")
                ).hexdigest(),
                "master_product_ids": set(),
            },
        )
        group["master_product_ids"].update(candidate["master_product_ids"])
    return [
        {
            **group,
            "master_product_ids": sorted(group["master_product_ids"]),
        }
        for _, group in sorted(grouped.items())
    ]


def _csv_rows_match(
    actual_rows: Sequence[dict[str, str]],
    expected_rows: Sequence[dict[str, str]],
    headers: Sequence[str],
) -> bool:
    return [
        {header: row.get(header, "") for header in headers} for row in actual_rows
    ] == [
        {header: row.get(header, "") for header in headers} for row in expected_rows
    ]


def plan_exact_semantic_duplicate_prune(
    *,
    masters_path: Path = DEFAULT_MASTERS,
    barcodes_path: Path = DEFAULT_BARCODES,
    rejected_masters_path: Path = DEFAULT_REJECTED_EXACT_MASTER_REPORT,
    rejected_barcodes_path: Path = DEFAULT_REJECTED_EXACT_BARCODE_REPORT,
    manifest_path: Path = DEFAULT_MANIFEST,
    vocabularies_path: Path = DEFAULT_CONFIG,
    expected_group_count: int,
    expected_master_count: int,
    expected_barcode_count: int,
) -> dict[str, Any]:
    """Plan removal using only exact groups already emitted by the validator."""
    if (
        expected_group_count <= 0
        or expected_master_count <= 0
        or expected_barcode_count <= 0
    ):
        raise CatalogToolError(
            "expected group, master, and barcode counts must be greater than zero"
        )
    resolved_paths = {
        masters_path.resolve(),
        barcodes_path.resolve(),
        rejected_masters_path.resolve(),
        rejected_barcodes_path.resolve(),
    }
    if len(resolved_paths) != 4:
        raise CatalogToolError("active datasets and rejected reports must use distinct paths")

    validation = validate_dataset(
        masters_path=masters_path,
        barcodes_path=barcodes_path,
        manifest_path=manifest_path,
        vocabularies_path=vocabularies_path,
    )
    master_rows, master_header_issues = _read_csv(masters_path, MASTER_HEADERS)
    barcode_rows, barcode_header_issues = _read_csv(barcodes_path, BARCODE_HEADERS)
    groups = _exact_semantic_groups(validation)
    target_ids = sorted(
        {
            master_id
            for group in groups
            for master_id in group["master_product_ids"]
        }
    )
    target_id_set = set(target_ids)
    group_ids_by_master: dict[str, list[str]] = {}
    for group in groups:
        for master_id in group["master_product_ids"]:
            group_ids_by_master.setdefault(master_id, []).append(group["duplicate_group_id"])

    target_masters = [
        row
        for row in master_rows
        if normalize_visible_text(row["master_product_id"]).lower() in target_id_set
    ]
    target_barcodes = [
        row
        for row in barcode_rows
        if normalize_visible_text(row["master_product_id"]).lower() in target_id_set
    ]
    retained_masters = [
        row
        for row in master_rows
        if normalize_visible_text(row["master_product_id"]).lower() not in target_id_set
    ]
    retained_barcodes = [
        row
        for row in barcode_rows
        if normalize_visible_text(row["master_product_id"]).lower() not in target_id_set
    ]
    master_by_id = {
        normalize_visible_text(row["master_product_id"]).lower(): row for row in target_masters
    }
    barcodes_by_master: dict[str, list[dict[str, str]]] = {}
    for row in target_barcodes:
        master_id = normalize_visible_text(row["master_product_id"]).lower()
        barcodes_by_master.setdefault(master_id, []).append(row)

    blockers: list[dict[str, Any]] = []
    for issue in [*master_header_issues, *barcode_header_issues]:
        if issue.severity == "error":
            blockers.append(issue.to_dict())
    other_blocking_codes = sorted(
        {
            issue["code"]
            for issue in validation["blocking_errors"]
            if issue["code"] != "exact_semantic_duplicate"
        }
    )
    if groups and other_blocking_codes:
        blockers.append(
            {
                "code": "unrelated_validation_errors",
                "message": "Dataset has blocking errors outside exact semantic duplicates",
                "blocking_codes": other_blocking_codes,
            }
        )
    if groups and len(groups) != expected_group_count:
        blockers.append(
            {
                "code": "unexpected_exact_group_count",
                "message": f"Expected {expected_group_count} exact groups, found {len(groups)}",
            }
        )
    if groups and len(target_ids) != expected_master_count:
        blockers.append(
            {
                "code": "unexpected_exact_master_count",
                "message": f"Expected {expected_master_count} exact-group masters, found {len(target_ids)}",
            }
        )
    if groups and len(target_barcodes) != expected_barcode_count:
        blockers.append(
            {
                "code": "unexpected_exact_barcode_count",
                "message": (
                    f"Expected {expected_barcode_count} exact-group barcode relations, "
                    f"found {len(target_barcodes)}"
                ),
            }
        )
    if groups and len(target_masters) != len(target_ids):
        blockers.append(
            {
                "code": "target_master_missing_or_duplicated",
                "message": "Every validator target must resolve to exactly one active master row",
            }
        )
    multi_group_masters = sorted(
        master_id for master_id, group_ids in group_ids_by_master.items() if len(set(group_ids)) != 1
    )
    if multi_group_masters:
        blockers.append(
            {
                "code": "master_in_multiple_exact_groups",
                "message": "A master belongs to more than one stable exact group",
                "master_product_ids": multi_group_masters,
            }
        )

    for master_id in target_ids:
        master = master_by_id.get(master_id)
        relations = barcodes_by_master.get(master_id, [])
        primary_rows = [row for row in relations if row["is_primary"] == "true"]
        if master is None or not relations:
            blockers.append(
                {
                    "code": "target_missing_barcode_relation",
                    "message": "Exact-group master has no relational barcode row",
                    "master_product_id": master_id,
                }
            )
            continue
        if len(primary_rows) != 1:
            blockers.append(
                {
                    "code": "target_primary_relation_count",
                    "message": "Exact-group master must have exactly one primary relation",
                    "master_product_id": master_id,
                    "primary_count": len(primary_rows),
                }
            )
            continue
        primary = primary_rows[0]
        if (
            normalize_barcode(primary["barcode"]) != normalize_barcode(master["primary_barcode"])
            or normalize_visible_text(primary["barcode_type"]).lower()
            != normalize_visible_text(master["barcode_type"]).lower()
        ):
            blockers.append(
                {
                    "code": "target_primary_relation_mismatch",
                    "message": "Exact-group master primary relation does not match the seed",
                    "master_product_id": master_id,
                }
            )

    target_codes = {
        normalize_barcode(row["barcode"]) for row in target_barcodes if normalize_barcode(row["barcode"])
    }
    shared_with_retained = sorted(
        {
            normalize_barcode(row["barcode"])
            for row in retained_barcodes
            if normalize_barcode(row["barcode"]) in target_codes
        }
    )
    if shared_with_retained:
        blockers.append(
            {
                "code": "target_barcode_shared_with_retained_master",
                "message": "A barcode slated for rejection is also owned by a retained master",
                "barcodes": shared_with_retained,
            }
        )

    rejected_master_rows = [
        {
            **{header: row.get(header, "") for header in MASTER_HEADERS},
            "rejection_reason": "exact_semantic_duplicate",
            "duplicate_group_id": group_ids_by_master[
                normalize_visible_text(row["master_product_id"]).lower()
            ][0],
        }
        for row in target_masters
    ]
    rejected_barcode_rows = [
        {
            **{header: row.get(header, "") for header in BARCODE_HEADERS},
            "rejection_reason": "exact_semantic_duplicate",
            "duplicate_group_id": group_ids_by_master[
                normalize_visible_text(row["master_product_id"]).lower()
            ][0],
        }
        for row in target_barcodes
    ]

    existing_rejected_masters: list[dict[str, str]] = []
    existing_rejected_barcodes: list[dict[str, str]] = []
    master_report_matches = False
    barcode_report_matches = False
    if rejected_masters_path.exists():
        existing_rejected_masters, report_issues = _read_csv(
            rejected_masters_path, REJECTED_EXACT_MASTER_HEADERS
        )
        master_report_matches = not report_issues and _csv_rows_match(
            existing_rejected_masters,
            rejected_master_rows,
            REJECTED_EXACT_MASTER_HEADERS,
        )
        if groups and not master_report_matches:
            blockers.append(
                {
                    "code": "existing_rejected_master_report_mismatch",
                    "message": "Existing rejected master report does not match current targets",
                }
            )
    if rejected_barcodes_path.exists():
        existing_rejected_barcodes, report_issues = _read_csv(
            rejected_barcodes_path, REJECTED_EXACT_BARCODE_HEADERS
        )
        barcode_report_matches = not report_issues and _csv_rows_match(
            existing_rejected_barcodes,
            rejected_barcode_rows,
            REJECTED_EXACT_BARCODE_HEADERS,
        )
        if groups and not barcode_report_matches:
            blockers.append(
                {
                    "code": "existing_rejected_barcode_report_mismatch",
                    "message": "Existing rejected barcode report does not match current targets",
                }
            )

    already_pruned = not groups
    if already_pruned:
        report_master_ids = {
            normalize_visible_text(row["master_product_id"]).lower()
            for row in existing_rejected_masters
        }
        report_group_ids = {
            normalize_visible_text(row["duplicate_group_id"])
            for row in existing_rejected_masters
        }
        report_group_by_master = {
            normalize_visible_text(row["master_product_id"]).lower(): normalize_visible_text(
                row["duplicate_group_id"]
            )
            for row in existing_rejected_masters
        }
        report_barcode_master_ids = {
            normalize_visible_text(row["master_product_id"]).lower()
            for row in existing_rejected_barcodes
        }
        report_barcode_ids = [
            normalize_visible_text(row["barcode_id"]).lower()
            for row in existing_rejected_barcodes
        ]
        report_barcodes_by_master: dict[str, list[dict[str, str]]] = {}
        for row in existing_rejected_barcodes:
            report_barcodes_by_master.setdefault(
                normalize_visible_text(row["master_product_id"]).lower(), []
            ).append(row)
        active_master_ids = {
            normalize_visible_text(row["master_product_id"]).lower() for row in master_rows
        }
        active_barcode_master_ids = {
            normalize_visible_text(row["master_product_id"]).lower() for row in barcode_rows
        }
        master_report_matches = (
            len(existing_rejected_masters) == expected_master_count
            and len(report_master_ids) == expected_master_count
            and len(report_group_ids) == expected_group_count
            and all(
                row.get("rejection_reason") == "exact_semantic_duplicate"
                for row in existing_rejected_masters
            )
            and not (report_master_ids & active_master_ids)
        )
        barcode_report_matches = (
            len(existing_rejected_barcodes) == expected_barcode_count
            and len(set(report_barcode_ids)) == expected_barcode_count
            and all(is_valid_uuid(barcode_id) for barcode_id in report_barcode_ids)
            and report_barcode_master_ids == report_master_ids
            and all(
                row.get("rejection_reason") == "exact_semantic_duplicate"
                and normalize_visible_text(row.get("duplicate_group_id"))
                == report_group_by_master.get(
                    normalize_visible_text(row.get("master_product_id")).lower()
                )
                for row in existing_rejected_barcodes
            )
            and all(
                len(
                    [
                        barcode
                        for barcode in report_barcodes_by_master.get(master_id, [])
                        if barcode.get("is_primary") == "true"
                        and normalize_barcode(barcode.get("barcode"))
                        == normalize_barcode(master.get("primary_barcode"))
                        and normalize_visible_text(barcode.get("barcode_type")).lower()
                        == normalize_visible_text(master.get("barcode_type")).lower()
                    ]
                )
                == 1
                for master_id, master in (
                    (
                        normalize_visible_text(row["master_product_id"]).lower(),
                        row,
                    )
                    for row in existing_rejected_masters
                )
            )
            and not (report_barcode_master_ids & active_barcode_master_ids)
        )
        if not master_report_matches or not barcode_report_matches:
            blockers.append(
                {
                    "code": "missing_or_invalid_exact_duplicate_audit",
                    "message": "No active exact groups exist and the prior audit reports are incomplete",
                }
            )

    group_size_distribution: dict[str, int] = {}
    for group in groups:
        size = str(len(group["master_product_ids"]))
        group_size_distribution[size] = group_size_distribution.get(size, 0) + 1
    return {
        "operation": "prune-exact-semantic-duplicates",
        "status": "no_op" if already_pruned and not blockers else "planned",
        "masters_before": len(master_rows),
        "barcodes_before": len(barcode_rows),
        "exact_group_count": len(groups),
        "exact_master_count": len(target_ids),
        "exact_barcode_count": len(target_barcodes),
        "expected_exact_barcode_count": expected_barcode_count,
        "group_size_distribution": group_size_distribution,
        "masters_after": len(retained_masters),
        "barcodes_after": len(retained_barcodes),
        "target_master_ids": target_ids,
        "groups": groups,
        "blockers": blockers,
        "can_apply": not blockers,
        "already_pruned": already_pruned,
        "master_report_matches": master_report_matches,
        "barcode_report_matches": barcode_report_matches,
        "_retained_masters": retained_masters,
        "_retained_barcodes": retained_barcodes,
        "_rejected_masters": rejected_master_rows,
        "_rejected_barcodes": rejected_barcode_rows,
    }


def exact_duplicate_prune_report_json(report: dict[str, Any]) -> str:
    public_report = {key: value for key, value in report.items() if not key.startswith("_")}
    return json.dumps(public_report, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def exact_duplicate_prune_human_report(report: dict[str, Any]) -> str:
    lines = [
        f"Exact semantic duplicate pruning: {report['status'].upper()}",
        f"Masters: {report['masters_before']} -> {report['masters_after']}",
        f"Barcodes: {report['barcodes_before']} -> {report['barcodes_after']}",
        f"Groups: {report['exact_group_count']}; masters: {report['exact_master_count']}",
        f"Group sizes: {stable_json(report['group_size_distribution'])}",
        f"Wrote datasets: {str(report['wrote_datasets']).lower()}",
        f"Wrote rejected reports: {str(report['wrote_rejected_reports']).lower()}",
    ]
    if report.get("seed_backup_path"):
        lines.append(f"Seed backup: {report['seed_backup_path']}")
    if report.get("barcode_backup_path"):
        lines.append(f"Barcode backup: {report['barcode_backup_path']}")
    for blocker in report["blockers"]:
        lines.append(f"BLOCKER {blocker['code']}: {blocker['message']}")
    return "\n".join(lines)


def _restore_file_from_backup(backup_path: Path, destination: Path) -> None:
    restore_temp = destination.parent / f".{destination.name}.{uuid.uuid4()}.restore.tmp"
    try:
        shutil.copy2(backup_path, restore_temp)
        os.replace(restore_temp, destination)
    finally:
        restore_temp.unlink(missing_ok=True)


def prune_exact_semantic_duplicates(
    *,
    masters_path: Path = DEFAULT_MASTERS,
    barcodes_path: Path = DEFAULT_BARCODES,
    rejected_masters_path: Path = DEFAULT_REJECTED_EXACT_MASTER_REPORT,
    rejected_barcodes_path: Path = DEFAULT_REJECTED_EXACT_BARCODE_REPORT,
    manifest_path: Path = DEFAULT_MANIFEST,
    vocabularies_path: Path = DEFAULT_CONFIG,
    backup_dir: Path = DEFAULT_BACKUP_DIR,
    expected_group_count: int,
    expected_master_count: int,
    expected_barcode_count: int,
    dry_run: bool = False,
) -> dict[str, Any]:
    plan = plan_exact_semantic_duplicate_prune(
        masters_path=masters_path,
        barcodes_path=barcodes_path,
        rejected_masters_path=rejected_masters_path,
        rejected_barcodes_path=rejected_barcodes_path,
        manifest_path=manifest_path,
        vocabularies_path=vocabularies_path,
        expected_group_count=expected_group_count,
        expected_master_count=expected_master_count,
        expected_barcode_count=expected_barcode_count,
    )
    plan.update(
        {
            "status": "blocked" if not plan["can_apply"] else plan["status"],
            "wrote_datasets": False,
            "wrote_rejected_reports": False,
            "seed_backup_path": None,
            "barcode_backup_path": None,
            "rejected_masters_path": str(rejected_masters_path),
            "rejected_barcodes_path": str(rejected_barcodes_path),
        }
    )
    if not plan["can_apply"] or plan["already_pruned"]:
        return plan
    if dry_run:
        plan["status"] = "dry_run"
        return plan

    candidate_seed = _write_csv_temp(masters_path, MASTER_HEADERS, plan["_retained_masters"])
    candidate_barcodes = _write_csv_temp(
        barcodes_path, BARCODE_HEADERS, plan["_retained_barcodes"]
    )
    candidate_master_report = _write_csv_temp(
        rejected_masters_path,
        REJECTED_EXACT_MASTER_HEADERS,
        plan["_rejected_masters"],
    )
    candidate_barcode_report = _write_csv_temp(
        rejected_barcodes_path,
        REJECTED_EXACT_BARCODE_HEADERS,
        plan["_rejected_barcodes"],
    )
    try:
        candidate_validation = validate_dataset(
            masters_path=candidate_seed,
            barcodes_path=candidate_barcodes,
            manifest_path=manifest_path,
            vocabularies_path=vocabularies_path,
        )
        candidate_sync = plan_primary_barcode_sync(
            masters_path=candidate_seed,
            barcodes_path=candidate_barcodes,
            vocabularies_path=vocabularies_path,
        )
        if (
            candidate_validation["blocking_error_count"] != 0
            or _exact_semantic_groups(candidate_validation)
            or candidate_validation["barcode_conflicts"]
            or candidate_sync["masters_total"] != plan["masters_after"]
            or candidate_sync["masters_valid"] != plan["masters_after"]
            or candidate_sync["already_correct"] != plan["masters_after"]
            or candidate_sync["would_insert"] != 0
            or candidate_sync["would_promote"] != 0
            or candidate_sync["conflict_count"] != 0
            or candidate_sync["input_error_count"] != 0
        ):
            plan.update(
                {
                    "status": "blocked",
                    "can_apply": False,
                    "post_validation": {
                        "blocking_error_count": candidate_validation["blocking_error_count"],
                        "exact_group_count": len(_exact_semantic_groups(candidate_validation)),
                        "barcode_conflicts": len(candidate_validation["barcode_conflicts"]),
                        "primary_sync": {
                            key: candidate_sync[key]
                            for key in (
                                "masters_total",
                                "masters_valid",
                                "already_correct",
                                "would_insert",
                                "would_promote",
                                "conflict_count",
                                "input_error_count",
                            )
                        },
                    },
                }
            )
            return plan

        backup_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        seed_hash = hashlib.sha256(masters_path.read_bytes()).hexdigest()
        barcode_hash = hashlib.sha256(barcodes_path.read_bytes()).hexdigest()
        seed_backup = backup_dir / f"master_catalog_seed.{timestamp}.{seed_hash[:12]}.csv"
        barcode_backup = backup_dir / f"master_catalog_barcodes.{timestamp}.{barcode_hash[:12]}.csv"
        shutil.copy2(masters_path, seed_backup)
        shutil.copy2(barcodes_path, barcode_backup)

        rejected_masters_path.parent.mkdir(parents=True, exist_ok=True)
        rejected_barcodes_path.parent.mkdir(parents=True, exist_ok=True)
        if not rejected_masters_path.exists():
            os.replace(candidate_master_report, rejected_masters_path)
        if not rejected_barcodes_path.exists():
            os.replace(candidate_barcode_report, rejected_barcodes_path)
        plan["wrote_rejected_reports"] = True

        os.replace(candidate_barcodes, barcodes_path)
        try:
            os.replace(candidate_seed, masters_path)
        except Exception:
            try:
                _restore_file_from_backup(barcode_backup, barcodes_path)
            except Exception as restore_error:
                raise CatalogToolError(
                    "Seed replace failed and relational barcode rollback also failed; "
                    f"restore manually from {barcode_backup}"
                ) from restore_error
            raise

        plan.update(
            {
                "status": "applied",
                "wrote_datasets": True,
                "seed_backup_path": str(seed_backup),
                "barcode_backup_path": str(barcode_backup),
                "seed_sha256_after": hashlib.sha256(masters_path.read_bytes()).hexdigest(),
                "barcode_sha256_after": hashlib.sha256(barcodes_path.read_bytes()).hexdigest(),
            }
        )
        return plan
    finally:
        candidate_seed.unlink(missing_ok=True)
        candidate_barcodes.unlink(missing_ok=True)
        candidate_master_report.unlink(missing_ok=True)
        candidate_barcode_report.unlink(missing_ok=True)


def _planner_entries(
    plan: dict[str, Any], domain: str, action: str
) -> list[dict[str, Any]]:
    bucket = plan.get(domain)
    if not isinstance(bucket, dict) or not isinstance(bucket.get(action), list):
        raise CatalogToolError(f"Import plan is missing {domain}.{action}")
    entries = bucket[action]
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("record"), dict):
            raise CatalogToolError(f"Import plan contains an invalid {domain}.{action} entry")
    return entries


def _plan_record_as_csv(record: dict[str, Any], headers: Sequence[str]) -> dict[str, str]:
    converted: dict[str, str] = {}
    for header in headers:
        value = record.get(header, "")
        if isinstance(value, bool):
            converted[header] = str(value).lower()
        elif value is None:
            converted[header] = ""
        else:
            converted[header] = str(value)
    return converted


def _catalog_csv_records_match(
    actual: dict[str, str], expected: dict[str, str], headers: Sequence[str]
) -> bool:
    for header in headers:
        actual_value = actual.get(header, "")
        expected_value = expected.get(header, "")
        if header in {"package_size", "confidence_score"}:
            try:
                if canonical_decimal(actual_value, field_name=header) != canonical_decimal(
                    expected_value, field_name=header
                ):
                    return False
            except ValueError:
                return False
        elif actual_value != expected_value:
            return False
    return True


def plan_preflight_blocker_prune(
    *,
    masters_path: Path = DEFAULT_MASTERS,
    barcodes_path: Path = DEFAULT_BARCODES,
    plan_path: Path = DEFAULT_PREFLIGHT_PLAN,
    snapshot_path: Path = DEFAULT_PREFLIGHT_SNAPSHOT,
    rejected_review_masters_path: Path = DEFAULT_REJECTED_PREFLIGHT_REVIEW_MASTER_REPORT,
    rejected_review_barcodes_path: Path = DEFAULT_REJECTED_PREFLIGHT_REVIEW_BARCODE_REPORT,
    rejected_conflict_masters_path: Path = DEFAULT_REJECTED_PREFLIGHT_CONFLICT_MASTER_REPORT,
    rejected_conflict_barcodes_path: Path = DEFAULT_REJECTED_PREFLIGHT_CONFLICT_BARCODE_REPORT,
    manifest_path: Path = DEFAULT_MANIFEST,
    vocabularies_path: Path = DEFAULT_CONFIG,
    expected_review_count: int,
    expected_conflict_count: int,
) -> dict[str, Any]:
    """Plan a conservative prune using only P1.3 REVIEW and CONFLICT actions."""
    if expected_review_count <= 0 or expected_conflict_count <= 0:
        raise CatalogToolError("expected review and conflict counts must be greater than zero")
    all_paths = [
        masters_path,
        barcodes_path,
        plan_path,
        snapshot_path,
        rejected_review_masters_path,
        rejected_review_barcodes_path,
        rejected_conflict_masters_path,
        rejected_conflict_barcodes_path,
    ]
    if len({path.resolve() for path in all_paths}) != len(all_paths):
        raise CatalogToolError("active datasets, planner inputs, and rejected reports must use distinct paths")

    plan = _read_json(plan_path)
    snapshot = _read_json(snapshot_path)
    blockers: list[dict[str, Any]] = []
    if plan.get("plan_version") != 1:
        raise CatalogToolError("Unsupported or missing import plan version")
    if snapshot.get("snapshot_version") != 1:
        raise CatalogToolError("Unsupported or missing snapshot version")

    # Reuse the canonical P1.3 hashing and snapshot contracts rather than
    # maintaining a second representation for this destructive operation.
    import catalog_importer

    unsigned_plan = {key: value for key, value in plan.items() if key != "plan_hash"}
    if plan.get("plan_hash") != catalog_importer.sha256_json(unsigned_plan):
        blockers.append(
            {
                "code": "invalid_plan_hash",
                "message": "Import plan hash is invalid; regenerate the plan",
            }
        )
    try:
        snapshot = catalog_importer.parse_snapshot(snapshot)
    except catalog_importer.ImporterError as error:
        raise CatalogToolError(f"Invalid import snapshot: {error}") from error
    if plan.get("snapshot_hash") != catalog_importer.sha256_json(snapshot):
        blockers.append(
            {
                "code": "snapshot_hash_mismatch",
                "message": "Import plan is not bound to the supplied snapshot",
            }
        )

    master_reviews = _planner_entries(plan, "masters", "reviews")
    master_conflicts = _planner_entries(plan, "masters", "conflicts")
    master_inserts = _planner_entries(plan, "masters", "inserts")
    master_updates = _planner_entries(plan, "masters", "updates")
    master_no_ops = _planner_entries(plan, "masters", "no_ops")
    barcode_reviews = _planner_entries(plan, "barcodes", "reviews")
    barcode_conflicts = _planner_entries(plan, "barcodes", "conflicts")
    barcode_inserts = _planner_entries(plan, "barcodes", "inserts")
    barcode_updates = _planner_entries(plan, "barcodes", "updates")
    barcode_no_ops = _planner_entries(plan, "barcodes", "no_ops")

    def master_ids(entries: Sequence[dict[str, Any]]) -> list[str]:
        return [
            normalize_visible_text(entry["record"].get("master_product_id")).lower()
            for entry in entries
        ]

    review_ids = master_ids(master_reviews)
    conflict_ids = master_ids(master_conflicts)
    review_id_set = set(review_ids)
    conflict_id_set = set(conflict_ids)
    target_ids = review_id_set | conflict_id_set
    insert_id_set = set(master_ids(master_inserts))
    if len(review_ids) != expected_review_count or len(review_id_set) != expected_review_count:
        blockers.append(
            {
                "code": "unexpected_review_master_count",
                "message": f"Expected {expected_review_count} unique REVIEW masters, found {len(review_id_set)}",
            }
        )
    if len(conflict_ids) != expected_conflict_count or len(conflict_id_set) != expected_conflict_count:
        blockers.append(
            {
                "code": "unexpected_conflict_master_count",
                "message": f"Expected {expected_conflict_count} unique CONFLICT masters, found {len(conflict_id_set)}",
            }
        )
    if review_id_set & conflict_id_set:
        blockers.append(
            {
                "code": "review_conflict_overlap",
                "message": "A master is classified as both REVIEW and CONFLICT",
            }
        )
    if master_updates or master_no_ops or barcode_updates or barcode_no_ops:
        blockers.append(
            {
                "code": "non_insert_survivor_actions",
                "message": "The source plan contains UPDATE or NO_OP actions; this prune only preserves INSERT",
            }
        )

    review_barcode_master_ids = set(master_ids(barcode_reviews))
    conflict_barcode_master_ids = set(master_ids(barcode_conflicts))
    if review_barcode_master_ids != review_id_set:
        blockers.append(
            {
                "code": "review_barcode_scope_mismatch",
                "message": "REVIEW barcode actions do not match REVIEW master actions",
            }
        )
    if conflict_barcode_master_ids != conflict_id_set:
        blockers.append(
            {
                "code": "conflict_barcode_scope_mismatch",
                "message": "CONFLICT barcode actions do not match CONFLICT master actions",
            }
        )

    master_rows, master_header_issues = _read_csv(masters_path, MASTER_HEADERS)
    barcode_rows, barcode_header_issues = _read_csv(barcodes_path, BARCODE_HEADERS)
    for issue in [*master_header_issues, *barcode_header_issues]:
        if issue.severity == "error":
            blockers.append(issue.to_dict())

    active_master_ids = [normalize_visible_text(row["master_product_id"]).lower() for row in master_rows]
    active_barcode_ids = [normalize_visible_text(row["barcode_id"]).lower() for row in barcode_rows]
    present_target_ids = target_ids & set(active_master_ids)
    if present_target_ids and present_target_ids != target_ids:
        blockers.append(
            {
                "code": "partial_preflight_prune",
                "message": "Only part of the planner-derived target set remains active",
            }
        )
    already_pruned = not present_target_ids

    retained_masters = [
        row
        for row in master_rows
        if normalize_visible_text(row["master_product_id"]).lower() not in target_ids
    ]
    retained_barcodes = [
        row
        for row in barcode_rows
        if normalize_visible_text(row["master_product_id"]).lower() not in target_ids
    ]
    retained_master_ids = {
        normalize_visible_text(row["master_product_id"]).lower() for row in retained_masters
    }
    plan_insert_barcode_ids = {
        normalize_visible_text(entry["record"].get("barcode_id")).lower()
        for entry in barcode_inserts
    }
    retained_barcode_ids = {
        normalize_visible_text(row["barcode_id"]).lower() for row in retained_barcodes
    }
    if retained_master_ids != insert_id_set:
        blockers.append(
            {
                "code": "retained_masters_not_exactly_insert_actions",
                "message": "Retained active masters do not exactly match planner INSERT actions",
            }
        )
    if retained_barcode_ids != plan_insert_barcode_ids:
        blockers.append(
            {
                "code": "retained_barcodes_not_exactly_insert_actions",
                "message": "Retained active barcodes do not exactly match planner INSERT actions",
            }
        )

    planned_insert_master_by_id = {
        normalize_visible_text(entry["record"].get("master_product_id")).lower(): entry
        for entry in master_inserts
    }
    planned_insert_barcode_by_id = {
        normalize_visible_text(entry["record"].get("barcode_id")).lower(): entry
        for entry in barcode_inserts
    }
    for row in retained_masters:
        master_id = normalize_visible_text(row["master_product_id"]).lower()
        planned = planned_insert_master_by_id.get(master_id)
        if planned is None or not _catalog_csv_records_match(
            row,
            _plan_record_as_csv(planned["record"], MASTER_HEADERS),
            MASTER_HEADERS,
        ):
            blockers.append(
                {
                    "code": "planner_insert_master_payload_mismatch",
                    "message": "Retained master no longer matches its planner INSERT payload",
                    "master_product_id": master_id,
                }
            )
    for row in retained_barcodes:
        barcode_id = normalize_visible_text(row["barcode_id"]).lower()
        planned = planned_insert_barcode_by_id.get(barcode_id)
        if planned is None or not _catalog_csv_records_match(
            row,
            _plan_record_as_csv(planned["record"], BARCODE_HEADERS),
            BARCODE_HEADERS,
        ):
            blockers.append(
                {
                    "code": "planner_insert_barcode_payload_mismatch",
                    "message": "Retained barcode no longer matches its planner INSERT payload",
                    "barcode_id": barcode_id,
                }
            )

    active_master_by_id = {
        normalize_visible_text(row["master_product_id"]).lower(): row for row in master_rows
    }
    active_barcode_by_id = {
        normalize_visible_text(row["barcode_id"]).lower(): row for row in barcode_rows
    }
    barcodes_by_master: dict[str, list[dict[str, str]]] = {}
    for row in barcode_rows:
        barcodes_by_master.setdefault(
            normalize_visible_text(row["master_product_id"]).lower(), []
        ).append(row)

    target_entries = [("review", entry) for entry in master_reviews] + [
        ("conflict", entry) for entry in master_conflicts
    ]
    target_barcode_entries = [("review", entry) for entry in barcode_reviews] + [
        ("conflict", entry) for entry in barcode_conflicts
    ]
    planned_barcode_by_master = {
        normalize_visible_text(entry["record"].get("master_product_id")).lower(): entry
        for _, entry in target_barcode_entries
    }
    if not already_pruned:
        for action, entry in target_entries:
            record = _plan_record_as_csv(entry["record"], MASTER_HEADERS)
            master_id = record["master_product_id"].lower()
            active_master = active_master_by_id.get(master_id)
            if active_master is None or not _catalog_csv_records_match(
                active_master, record, MASTER_HEADERS
            ):
                blockers.append(
                    {
                        "code": "planner_master_record_mismatch",
                        "message": f"Active {action.upper()} master no longer matches the source plan",
                        "master_product_id": master_id,
                    }
                )
            relations = barcodes_by_master.get(master_id, [])
            primary_relations = [row for row in relations if row.get("is_primary") == "true"]
            planned_barcode = planned_barcode_by_master.get(master_id)
            if len(relations) != 1 or len(primary_relations) != 1 or planned_barcode is None:
                blockers.append(
                    {
                        "code": "target_primary_relation_count",
                        "message": "Every prune target must have exactly one primary barcode relation",
                        "master_product_id": master_id,
                    }
                )
                continue
            planned_barcode_record = _plan_record_as_csv(planned_barcode["record"], BARCODE_HEADERS)
            if not _catalog_csv_records_match(
                relations[0], planned_barcode_record, BARCODE_HEADERS
            ):
                blockers.append(
                    {
                        "code": "planner_barcode_record_mismatch",
                        "message": "Active target barcode no longer matches the source plan",
                        "master_product_id": master_id,
                    }
                )

    remote_barcodes = snapshot.get("global_barcodes")
    if not isinstance(remote_barcodes, list):
        raise CatalogToolError("Snapshot global_barcodes must be an array")
    hosted_identity_by_master: dict[str, tuple[str, str]] = {}
    for entry in master_conflicts:
        record = entry["record"]
        master_id = normalize_visible_text(record.get("master_product_id")).lower()
        code = normalize_barcode(record.get("primary_barcode"))
        owners = [
            row
            for row in remote_barcodes
            if isinstance(row, dict)
            and row.get("deleted_at") is None
            and row.get("status") == "active"
            and normalize_barcode(row.get("barcode")) == code
            and normalize_visible_text(row.get("master_product_id")).lower() != master_id
        ]
        if len(owners) != 1:
            blockers.append(
                {
                    "code": "hosted_conflict_identity_not_unique",
                    "message": "The snapshot does not expose exactly one active Hosted owner for the conflict",
                    "master_product_id": master_id,
                }
            )
        else:
            hosted_identity_by_master[master_id] = (
                normalize_visible_text(owners[0].get("master_product_id")).lower(),
                normalize_visible_text(owners[0].get("id")).lower(),
            )

    def rejected_master_rows(
        entries: Sequence[dict[str, Any]], rejection_reason: str, *, hosted: bool
    ) -> list[dict[str, str]]:
        rows: list[dict[str, str]] = []
        for entry in entries:
            planned = _plan_record_as_csv(entry["record"], MASTER_HEADERS)
            row = dict(active_master_by_id.get(planned["master_product_id"].lower(), planned))
            row.update(rejection_reason=rejection_reason, planner_reason=str(entry.get("reason", "")))
            if hosted:
                owner_id, barcode_id = hosted_identity_by_master.get(
                    row["master_product_id"].lower(), ("", "")
                )
                row.update(hosted_owner_master_id=owner_id, hosted_barcode_id=barcode_id)
            rows.append(row)
        return rows

    def rejected_barcode_rows(
        entries: Sequence[dict[str, Any]], rejection_reason: str, *, hosted: bool
    ) -> list[dict[str, str]]:
        rows: list[dict[str, str]] = []
        for entry in entries:
            planned = _plan_record_as_csv(entry["record"], BARCODE_HEADERS)
            row = dict(active_barcode_by_id.get(planned["barcode_id"].lower(), planned))
            row.update(rejection_reason=rejection_reason, planner_reason=str(entry.get("reason", "")))
            if hosted:
                owner_id, barcode_id = hosted_identity_by_master.get(
                    row["master_product_id"].lower(), ("", "")
                )
                row.update(hosted_owner_master_id=owner_id, hosted_barcode_id=barcode_id)
            rows.append(row)
        return rows

    report_specs: list[tuple[Path, Sequence[str], list[dict[str, str]]]] = [
        (
            rejected_review_masters_path,
            REJECTED_PREFLIGHT_REVIEW_MASTER_HEADERS,
            rejected_master_rows(master_reviews, "near_semantic_duplicate_review", hosted=False),
        ),
        (
            rejected_review_barcodes_path,
            REJECTED_PREFLIGHT_REVIEW_BARCODE_HEADERS,
            rejected_barcode_rows(barcode_reviews, "near_semantic_duplicate_review", hosted=False),
        ),
        (
            rejected_conflict_masters_path,
            REJECTED_PREFLIGHT_CONFLICT_MASTER_HEADERS,
            rejected_master_rows(master_conflicts, "hosted_catalog_conflict", hosted=True),
        ),
        (
            rejected_conflict_barcodes_path,
            REJECTED_PREFLIGHT_CONFLICT_BARCODE_HEADERS,
            rejected_barcode_rows(barcode_conflicts, "hosted_catalog_conflict", hosted=True),
        ),
    ]
    report_matches: dict[str, bool] = {}
    for path, headers, expected_rows in report_specs:
        matches = False
        if path.exists():
            actual_rows, issues = _read_csv(path, headers)
            matches = (
                not issues
                and len(actual_rows) == len(expected_rows)
                and all(
                    _catalog_csv_records_match(actual, expected, headers)
                    for actual, expected in zip(actual_rows, expected_rows)
                )
            )
            if not matches:
                blockers.append(
                    {
                        "code": "existing_rejected_report_mismatch",
                        "message": f"Existing rejected report does not match planner targets: {path.name}",
                    }
                )
        report_matches[path.name] = matches
    if already_pruned and not all(report_matches.values()):
        blockers.append(
            {
                "code": "missing_rejected_reports_for_no_op",
                "message": "Planner targets are already absent but their audit reports are incomplete",
            }
        )

    return {
        "operation": "prune-preflight-blockers",
        "status": "no_op" if already_pruned and not blockers else "planned",
        "import_batch_id": plan.get("import_batch_id"),
        "masters_before": len(master_rows),
        "barcodes_before": len(barcode_rows),
        "review_master_count": len(review_id_set),
        "conflict_master_count": len(conflict_id_set),
        "target_overlap_count": len(review_id_set & conflict_id_set),
        "target_master_count": len(target_ids),
        "target_barcode_count": len(review_barcode_master_ids | conflict_barcode_master_ids),
        "masters_after": len(retained_masters),
        "barcodes_after": len(retained_barcodes),
        "blockers": blockers,
        "can_apply": not blockers,
        "already_pruned": already_pruned,
        "report_matches": report_matches,
        "_retained_masters": retained_masters,
        "_retained_barcodes": retained_barcodes,
        "_report_specs": report_specs,
    }


def preflight_blocker_prune_report_json(report: dict[str, Any]) -> str:
    public_report = {key: value for key, value in report.items() if not key.startswith("_")}
    return json.dumps(public_report, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def preflight_blocker_prune_human_report(report: dict[str, Any]) -> str:
    lines = [
        f"Preflight blocker pruning: {report['status'].upper()}",
        f"Masters: {report['masters_before']} -> {report['masters_after']}",
        f"Barcodes: {report['barcodes_before']} -> {report['barcodes_after']}",
        f"Review masters: {report['review_master_count']}; conflict masters: {report['conflict_master_count']}",
        f"Wrote datasets: {str(report['wrote_datasets']).lower()}",
        f"Wrote rejected reports: {str(report['wrote_rejected_reports']).lower()}",
    ]
    if report.get("seed_backup_path"):
        lines.append(f"Seed backup: {report['seed_backup_path']}")
    if report.get("barcode_backup_path"):
        lines.append(f"Barcode backup: {report['barcode_backup_path']}")
    for blocker in report["blockers"]:
        lines.append(f"BLOCKER {blocker['code']}: {blocker['message']}")
    return "\n".join(lines)


def prune_preflight_blockers(
    *,
    masters_path: Path = DEFAULT_MASTERS,
    barcodes_path: Path = DEFAULT_BARCODES,
    plan_path: Path = DEFAULT_PREFLIGHT_PLAN,
    snapshot_path: Path = DEFAULT_PREFLIGHT_SNAPSHOT,
    rejected_review_masters_path: Path = DEFAULT_REJECTED_PREFLIGHT_REVIEW_MASTER_REPORT,
    rejected_review_barcodes_path: Path = DEFAULT_REJECTED_PREFLIGHT_REVIEW_BARCODE_REPORT,
    rejected_conflict_masters_path: Path = DEFAULT_REJECTED_PREFLIGHT_CONFLICT_MASTER_REPORT,
    rejected_conflict_barcodes_path: Path = DEFAULT_REJECTED_PREFLIGHT_CONFLICT_BARCODE_REPORT,
    manifest_path: Path = DEFAULT_MANIFEST,
    vocabularies_path: Path = DEFAULT_CONFIG,
    backup_dir: Path = DEFAULT_BACKUP_DIR,
    expected_review_count: int,
    expected_conflict_count: int,
    dry_run: bool = False,
) -> dict[str, Any]:
    plan = plan_preflight_blocker_prune(
        masters_path=masters_path,
        barcodes_path=barcodes_path,
        plan_path=plan_path,
        snapshot_path=snapshot_path,
        rejected_review_masters_path=rejected_review_masters_path,
        rejected_review_barcodes_path=rejected_review_barcodes_path,
        rejected_conflict_masters_path=rejected_conflict_masters_path,
        rejected_conflict_barcodes_path=rejected_conflict_barcodes_path,
        manifest_path=manifest_path,
        vocabularies_path=vocabularies_path,
        expected_review_count=expected_review_count,
        expected_conflict_count=expected_conflict_count,
    )
    plan.update(
        {
            "status": "blocked" if not plan["can_apply"] else plan["status"],
            "wrote_datasets": False,
            "wrote_rejected_reports": False,
            "seed_backup_path": None,
            "barcode_backup_path": None,
        }
    )
    if not plan["can_apply"] or plan["already_pruned"]:
        return plan
    if dry_run:
        plan["status"] = "dry_run"
        return plan

    candidate_seed = _write_csv_temp(masters_path, MASTER_HEADERS, plan["_retained_masters"])
    candidate_barcodes = _write_csv_temp(
        barcodes_path, BARCODE_HEADERS, plan["_retained_barcodes"]
    )
    report_candidates = [
        (path, _write_csv_temp(path, headers, rows))
        for path, headers, rows in plan["_report_specs"]
    ]
    created_reports: list[Path] = []
    barcode_replaced = False
    seed_replaced = False
    try:
        candidate_validation = validate_dataset(
            masters_path=candidate_seed,
            barcodes_path=candidate_barcodes,
            manifest_path=manifest_path,
            vocabularies_path=vocabularies_path,
        )
        candidate_sync = plan_primary_barcode_sync(
            masters_path=candidate_seed,
            barcodes_path=candidate_barcodes,
            vocabularies_path=vocabularies_path,
        )
        if (
            candidate_validation["blocking_error_count"] != 0
            or candidate_validation["warning_count"] != 0
            or candidate_validation["barcode_conflicts"]
            or candidate_sync["masters_total"] != plan["masters_after"]
            or candidate_sync["masters_valid"] != plan["masters_after"]
            or candidate_sync["already_correct"] != plan["masters_after"]
            or candidate_sync["would_insert"] != 0
            or candidate_sync["would_promote"] != 0
            or candidate_sync["conflict_count"] != 0
            or candidate_sync["input_error_count"] != 0
        ):
            plan.update(
                {
                    "status": "blocked",
                    "can_apply": False,
                    "post_validation": {
                        "blocking_error_count": candidate_validation["blocking_error_count"],
                        "warning_count": candidate_validation["warning_count"],
                        "barcode_conflicts": len(candidate_validation["barcode_conflicts"]),
                        "primary_sync": {
                            key: candidate_sync[key]
                            for key in (
                                "masters_total",
                                "masters_valid",
                                "already_correct",
                                "would_insert",
                                "would_promote",
                                "conflict_count",
                                "input_error_count",
                            )
                        },
                    },
                }
            )
            return plan

        backup_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        seed_hash = hashlib.sha256(masters_path.read_bytes()).hexdigest()
        barcode_hash = hashlib.sha256(barcodes_path.read_bytes()).hexdigest()
        seed_backup = backup_dir / f"master_catalog_seed.{timestamp}.{seed_hash[:12]}.csv"
        barcode_backup = backup_dir / f"master_catalog_barcodes.{timestamp}.{barcode_hash[:12]}.csv"
        shutil.copy2(masters_path, seed_backup)
        shutil.copy2(barcodes_path, barcode_backup)

        for (report_path, _, _), (_, candidate_report) in zip(
            plan["_report_specs"], report_candidates
        ):
            report_path.parent.mkdir(parents=True, exist_ok=True)
            if not report_path.exists():
                os.replace(candidate_report, report_path)
                created_reports.append(report_path)
        plan["wrote_rejected_reports"] = bool(created_reports)

        os.replace(candidate_barcodes, barcodes_path)
        barcode_replaced = True
        os.replace(candidate_seed, masters_path)
        seed_replaced = True

        plan.update(
            {
                "status": "applied",
                "wrote_datasets": True,
                "seed_backup_path": str(seed_backup),
                "barcode_backup_path": str(barcode_backup),
                "seed_sha256_after": hashlib.sha256(masters_path.read_bytes()).hexdigest(),
                "barcode_sha256_after": hashlib.sha256(barcodes_path.read_bytes()).hexdigest(),
            }
        )
        return plan
    except Exception as operation_error:
        rollback_errors: list[str] = []
        for was_replaced, backup, destination in (
            (seed_replaced, seed_backup if seed_replaced else None, masters_path),
            (barcode_replaced, barcode_backup if barcode_replaced else None, barcodes_path),
        ):
            if not was_replaced or backup is None:
                continue
            try:
                _restore_file_from_backup(backup, destination)
            except Exception as rollback_error:
                rollback_errors.append(f"{destination}: {rollback_error}")
        for path in created_reports:
            path.unlink(missing_ok=True)
        if rollback_errors:
            raise CatalogToolError(
                "Preflight prune failed and dataset rollback was incomplete; "
                + "; ".join(rollback_errors)
            ) from operation_error
        raise
    finally:
        candidate_seed.unlink(missing_ok=True)
        candidate_barcodes.unlink(missing_ok=True)
        for _, candidate in report_candidates:
            candidate.unlink(missing_ok=True)


def _path(value: str) -> Path:
    return Path(value).expanduser().resolve()


def _add_validation_paths(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--masters", type=_path, default=DEFAULT_MASTERS)
    parser.add_argument("--barcodes", type=_path, default=DEFAULT_BARCODES)
    parser.add_argument("--manifest", type=_path, default=DEFAULT_MANIFEST)
    parser.add_argument("--vocabularies", type=_path, default=DEFAULT_CONFIG)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate_parser = subparsers.add_parser("validate", help="Validate without changing CSV files")
    _add_validation_paths(validate_parser)

    dry_run_parser = subparsers.add_parser(
        "dry-run", help="Validate and emit a deterministic machine-readable report"
    )
    _add_validation_paths(dry_run_parser)
    dry_run_parser.add_argument("--report", type=_path, help="Write JSON report to this path")

    allocate_parser = subparsers.add_parser(
        "allocate-ids", help="Explicitly persist missing UUIDs in the two CSV files"
    )
    allocate_parser.add_argument("--masters", type=_path, default=DEFAULT_MASTERS)
    allocate_parser.add_argument("--barcodes", type=_path, default=DEFAULT_BARCODES)

    sync_parser = subparsers.add_parser(
        "sync-primary-barcodes",
        help="Materialize missing primary barcode relations from the master seed",
    )
    _add_validation_paths(sync_parser)
    sync_parser.add_argument("--backup-dir", type=_path, default=DEFAULT_BACKUP_DIR)
    sync_parser.add_argument("--dry-run", action="store_true", help="Report changes without writing")
    sync_parser.add_argument("--report", type=_path, help="Write a machine-readable JSON report")

    prune_parser = subparsers.add_parser(
        "prune-invalid-barcode-masters",
        help="Remove the validator-confirmed invalid-barcode masters from the active seed",
    )
    _add_validation_paths(prune_parser)
    prune_parser.add_argument(
        "--rejected-report",
        type=_path,
        default=DEFAULT_REJECTED_INVALID_BARCODE_REPORT,
    )
    prune_parser.add_argument("--backup-dir", type=_path, default=DEFAULT_BACKUP_DIR)
    prune_parser.add_argument("--expected-count", type=int, default=56)
    prune_parser.add_argument("--dry-run", action="store_true", help="Report changes without writing")
    prune_parser.add_argument("--report", type=_path, help="Write a machine-readable JSON report")

    exact_prune_parser = subparsers.add_parser(
        "prune-exact-semantic-duplicates",
        help="Remove every master in validator-confirmed exact semantic groups",
    )
    _add_validation_paths(exact_prune_parser)
    exact_prune_parser.add_argument(
        "--rejected-masters",
        type=_path,
        default=DEFAULT_REJECTED_EXACT_MASTER_REPORT,
    )
    exact_prune_parser.add_argument(
        "--rejected-barcodes",
        type=_path,
        default=DEFAULT_REJECTED_EXACT_BARCODE_REPORT,
    )
    exact_prune_parser.add_argument("--backup-dir", type=_path, default=DEFAULT_BACKUP_DIR)
    exact_prune_parser.add_argument("--expected-group-count", type=int, required=True)
    exact_prune_parser.add_argument("--expected-master-count", type=int, required=True)
    exact_prune_parser.add_argument("--expected-barcode-count", type=int, required=True)
    exact_prune_parser.add_argument(
        "--dry-run", action="store_true", help="Report changes without writing"
    )
    exact_prune_parser.add_argument("--report", type=_path, help="Write a machine-readable JSON report")

    preflight_prune_parser = subparsers.add_parser(
        "prune-preflight-blockers",
        help="Remove exactly the REVIEW and CONFLICT masters from a P1.3 import plan",
    )
    _add_validation_paths(preflight_prune_parser)
    preflight_prune_parser.add_argument("--plan", type=_path, default=DEFAULT_PREFLIGHT_PLAN)
    preflight_prune_parser.add_argument(
        "--snapshot", type=_path, default=DEFAULT_PREFLIGHT_SNAPSHOT
    )
    preflight_prune_parser.add_argument(
        "--rejected-review-masters",
        type=_path,
        default=DEFAULT_REJECTED_PREFLIGHT_REVIEW_MASTER_REPORT,
    )
    preflight_prune_parser.add_argument(
        "--rejected-review-barcodes",
        type=_path,
        default=DEFAULT_REJECTED_PREFLIGHT_REVIEW_BARCODE_REPORT,
    )
    preflight_prune_parser.add_argument(
        "--rejected-conflict-masters",
        type=_path,
        default=DEFAULT_REJECTED_PREFLIGHT_CONFLICT_MASTER_REPORT,
    )
    preflight_prune_parser.add_argument(
        "--rejected-conflict-barcodes",
        type=_path,
        default=DEFAULT_REJECTED_PREFLIGHT_CONFLICT_BARCODE_REPORT,
    )
    preflight_prune_parser.add_argument("--backup-dir", type=_path, default=DEFAULT_BACKUP_DIR)
    preflight_prune_parser.add_argument("--expected-review-count", type=int, required=True)
    preflight_prune_parser.add_argument("--expected-conflict-count", type=int, required=True)
    preflight_prune_parser.add_argument(
        "--dry-run", action="store_true", help="Report changes without writing"
    )
    preflight_prune_parser.add_argument(
        "--report", type=_path, help="Write a machine-readable JSON report"
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "allocate-ids":
            result = allocate_ids(masters_path=args.masters, barcodes_path=args.barcodes)
            print(json.dumps(result, sort_keys=True))
            return 0

        if args.command == "sync-primary-barcodes":
            result = sync_primary_barcodes(
                masters_path=args.masters,
                barcodes_path=args.barcodes,
                manifest_path=args.manifest,
                vocabularies_path=args.vocabularies,
                backup_dir=args.backup_dir,
                dry_run=args.dry_run,
            )
            if args.report:
                args.report.parent.mkdir(parents=True, exist_ok=True)
                args.report.write_text(
                    primary_barcode_sync_report_json(result), encoding="utf-8", newline="\n"
                )
            print(primary_barcode_sync_human_report(result))
            return 0 if result["can_apply"] else 1

        if args.command == "prune-invalid-barcode-masters":
            result = prune_invalid_barcode_masters(
                masters_path=args.masters,
                barcodes_path=args.barcodes,
                rejected_report_path=args.rejected_report,
                manifest_path=args.manifest,
                vocabularies_path=args.vocabularies,
                backup_dir=args.backup_dir,
                expected_count=args.expected_count,
                dry_run=args.dry_run,
            )
            if args.report:
                args.report.parent.mkdir(parents=True, exist_ok=True)
                args.report.write_text(
                    invalid_barcode_prune_report_json(result), encoding="utf-8", newline="\n"
                )
            print(invalid_barcode_prune_human_report(result))
            return 0 if result["can_apply"] else 1

        if args.command == "prune-exact-semantic-duplicates":
            result = prune_exact_semantic_duplicates(
                masters_path=args.masters,
                barcodes_path=args.barcodes,
                rejected_masters_path=args.rejected_masters,
                rejected_barcodes_path=args.rejected_barcodes,
                manifest_path=args.manifest,
                vocabularies_path=args.vocabularies,
                backup_dir=args.backup_dir,
                expected_group_count=args.expected_group_count,
                expected_master_count=args.expected_master_count,
                expected_barcode_count=args.expected_barcode_count,
                dry_run=args.dry_run,
            )
            if args.report:
                args.report.parent.mkdir(parents=True, exist_ok=True)
                args.report.write_text(
                    exact_duplicate_prune_report_json(result), encoding="utf-8", newline="\n"
                )
            print(exact_duplicate_prune_human_report(result))
            return 0 if result["can_apply"] else 1

        if args.command == "prune-preflight-blockers":
            result = prune_preflight_blockers(
                masters_path=args.masters,
                barcodes_path=args.barcodes,
                plan_path=args.plan,
                snapshot_path=args.snapshot,
                rejected_review_masters_path=args.rejected_review_masters,
                rejected_review_barcodes_path=args.rejected_review_barcodes,
                rejected_conflict_masters_path=args.rejected_conflict_masters,
                rejected_conflict_barcodes_path=args.rejected_conflict_barcodes,
                manifest_path=args.manifest,
                vocabularies_path=args.vocabularies,
                backup_dir=args.backup_dir,
                expected_review_count=args.expected_review_count,
                expected_conflict_count=args.expected_conflict_count,
                dry_run=args.dry_run,
            )
            if args.report:
                args.report.parent.mkdir(parents=True, exist_ok=True)
                args.report.write_text(
                    preflight_blocker_prune_report_json(result), encoding="utf-8", newline="\n"
                )
            print(preflight_blocker_prune_human_report(result))
            return 0 if result["can_apply"] else 1

        report = validate_dataset(
            masters_path=args.masters,
            barcodes_path=args.barcodes,
            manifest_path=args.manifest,
            vocabularies_path=args.vocabularies,
        )
        if args.command == "validate":
            print(human_report(report))
        else:
            serialized = report_json(report)
            if args.report:
                args.report.parent.mkdir(parents=True, exist_ok=True)
                args.report.write_text(serialized, encoding="utf-8", newline="\n")
                print(human_report(report))
                print(f"JSON report: {args.report}")
            else:
                print(human_report(report), file=sys.stderr)
                sys.stdout.write(serialized)
        return 0 if report["valid"] else 1
    except CatalogToolError as error:
        print(f"TOOL ERROR: {error}", file=sys.stderr)
        return 2
    except OSError as error:
        print(f"I/O ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
