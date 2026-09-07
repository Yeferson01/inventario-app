#!/usr/bin/env python3
"""Local-only tooling for the CronosManagement master catalog dataset."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import sys
import tempfile
import unicodedata
import uuid
from dataclasses import asdict, dataclass, field as dataclass_field
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
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "allocate-ids":
            result = allocate_ids(masters_path=args.masters, barcodes_path=args.barcodes)
            print(json.dumps(result, sort_keys=True))
            return 0

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
