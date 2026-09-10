#!/usr/bin/env python3
"""Build deterministic A2.2 technical and promotion-readiness subsets."""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
import tempfile
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any, Sequence


CATALOG_IMPORT_DIR = Path(__file__).resolve().parents[1]
if str(CATALOG_IMPORT_DIR) not in sys.path:
    sys.path.insert(0, str(CATALOG_IMPORT_DIR))

import catalog_tool  # noqa: E402
from resolution import candidate_resolution  # noqa: E402
from resolution import category_mapping  # noqa: E402


TECHNICAL_READY_HEADERS = [
    "primary_barcode",
    "barcode_type",
    "name",
    "brand",
    "category_name",
    "package_size",
    "package_unit",
    "unit_type",
    "source",
    "verification_status",
    "confidence_score",
    "source_reference",
    "rights_class",
    "rights_reference",
    "resolution_record_sha256",
    "category_mapping_record_sha256",
    "readiness_record_sha256",
]

BLOCKED_HEADERS = [
    "barcode",
    "technical_status",
    "technical_reason",
    "mapping_status",
    "has_name",
    "has_category",
    "rights_class",
    "resolution_record_sha256",
    "category_mapping_record_sha256",
]

MASTER_PROMOTION_HEADERS = [
    *TECHNICAL_READY_HEADERS,
    "promotion_rights_status",
    "promotion_reason",
]

TECHNICAL_REASONS = {
    "category_not_mapped",
    "missing_name",
    "invalid_input_provenance",
}
PROMOTION_RIGHTS_STATUSES = {"odbl_sidecar_only", "promotion_compatible"}
RIGHTS_STATUS_BY_CLASS = {
    "open_dataset_odbl_share_alike": "odbl_sidecar_only",
}
PROMOTION_REASON = "independent_promotion_rights"

READINESS_CONTRACT_VERSION = "1.0.0"
# Technical confidence for A2.2 v1. It reflects a valid GTIN, Colombia OFF
# evidence, an available factual name, and a curated Cronos category. It is
# not GS1 or manufacturer verification.
TECHNICAL_CONFIDENCE_SCORE_V1 = "0.70"

UNIT_TYPE = "unidad"
SOURCE = "open_dataset"
VERIFICATION_STATUS = "unverified"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
CSV_FIELD_SIZE_LIMIT = 64 * 1024 * 1024


class PromotionReadinessToolError(Exception):
    """Usage, I/O, or configuration error (exit code 2)."""


class PromotionReadinessValidationError(Exception):
    """Invalid inputs or generated outputs (exit code 1)."""


def _path(value: str) -> Path:
    return Path(value).expanduser().resolve()


def _trim(value: Any) -> str:
    """Trim exterior whitespace only; do not rewrite source wording."""
    return ("" if value is None else str(value)).strip()


def _read_exact_csv(
    path: Path,
    headers: Sequence[str],
    *,
    input_name: str,
    barcode_field: str,
) -> list[dict[str, str]]:
    csv.field_size_limit(CSV_FIELD_SIZE_LIMIT)
    try:
        handle = path.open("r", encoding="utf-8-sig", newline="")
    except OSError as error:
        raise PromotionReadinessToolError(f"Cannot read {input_name} {path}: {error}") from error

    rows: list[dict[str, str]] = []
    seen_barcodes: set[str] = set()
    try:
        with handle:
            reader = csv.reader(handle, strict=True)
            try:
                actual_headers = next(reader)
            except StopIteration as error:
                raise PromotionReadinessValidationError(
                    f"{input_name} is empty and has no header"
                ) from error
            if actual_headers != list(headers):
                raise PromotionReadinessValidationError(
                    f"{input_name} header is incompatible with its contract"
                )
            for row_number, raw_row in enumerate(reader, start=2):
                if len(raw_row) != len(headers):
                    raise PromotionReadinessValidationError(
                        f"{input_name} row {row_number} has an invalid field count"
                    )
                row = dict(zip(headers, raw_row, strict=True))
                barcode = row[barcode_field]
                if not barcode:
                    raise PromotionReadinessValidationError(
                        f"{input_name} row {row_number} has an empty barcode"
                    )
                if barcode in seen_barcodes:
                    raise PromotionReadinessValidationError(
                        f"Duplicate {input_name} barcode: {barcode}"
                    )
                seen_barcodes.add(barcode)
                rows.append(row)
    except (csv.Error, UnicodeError) as error:
        raise PromotionReadinessValidationError(
            f"Cannot parse {input_name}: {error}"
        ) from error
    return rows


def _expected_hash(row: dict[str, str], headers: Sequence[str], hash_field: str) -> str:
    return catalog_tool.record_hash(
        {header: row[header] for header in headers if header != hash_field}
    )


def _validate_resolution_rows(rows: Sequence[dict[str, str]]) -> None:
    for row_number, row in enumerate(rows, start=2):
        actual = row["resolution_record_sha256"]
        if not SHA256_RE.fullmatch(actual) or actual != _expected_hash(
            row,
            candidate_resolution.RESOLUTION_HEADERS,
            "resolution_record_sha256",
        ):
            raise PromotionReadinessValidationError(
                f"Resolution row {row_number} has an invalid resolution_record_sha256"
            )


def _validate_mapping_rows(
    rows: Sequence[dict[str, str]], categories: Sequence[str]
) -> None:
    allowed_categories = set(categories)
    for row_number, row in enumerate(rows, start=2):
        status = row["mapping_status"]
        category = row["cronos_category_candidate"]
        reason = row["mapping_reason"]
        if status not in category_mapping.MAPPING_STATUSES:
            raise PromotionReadinessValidationError(
                f"Mapping row {row_number} has an invalid mapping_status"
            )
        if category and category not in allowed_categories:
            raise PromotionReadinessValidationError(
                f"Mapping row {row_number} category is outside the P1.2 vocabulary"
            )
        if (status == "mapped") != bool(category):
            raise PromotionReadinessValidationError(
                f"Mapping row {row_number} has an inconsistent category decision"
            )
        if reason not in category_mapping.REASONS_BY_STATUS[status]:
            raise PromotionReadinessValidationError(
                f"Mapping row {row_number} has an incompatible mapping_reason"
            )
        if not SHA256_RE.fullmatch(row["ruleset_sha256"]):
            raise PromotionReadinessValidationError(
                f"Mapping row {row_number} has an invalid ruleset_sha256"
            )
        if not SHA256_RE.fullmatch(row["resolution_record_sha256"]):
            raise PromotionReadinessValidationError(
                f"Mapping row {row_number} has an invalid resolution_record_sha256"
            )
        actual = row["category_mapping_record_sha256"]
        if not SHA256_RE.fullmatch(actual) or actual != _expected_hash(
            row,
            category_mapping.CATEGORY_MAPPING_HEADERS,
            "category_mapping_record_sha256",
        ):
            raise PromotionReadinessValidationError(
                f"Mapping row {row_number} has an invalid category_mapping_record_sha256"
            )


def _load_inputs(
    resolution_path: Path,
    mapping_path: Path,
    categories: Sequence[str],
) -> list[tuple[dict[str, str], dict[str, str]]]:
    resolution_rows = _read_exact_csv(
        resolution_path,
        candidate_resolution.RESOLUTION_HEADERS,
        input_name="resolution input",
        barcode_field="barcode",
    )
    mapping_rows = _read_exact_csv(
        mapping_path,
        category_mapping.CATEGORY_MAPPING_HEADERS,
        input_name="mapping input",
        barcode_field="barcode",
    )
    _validate_resolution_rows(resolution_rows)
    _validate_mapping_rows(mapping_rows, categories)

    resolution_by_barcode = {row["barcode"]: row for row in resolution_rows}
    mapping_by_barcode = {row["barcode"]: row for row in mapping_rows}
    if set(resolution_by_barcode) != set(mapping_by_barcode):
        raise PromotionReadinessValidationError(
            "Resolution and mapping barcode sets are different"
        )

    joined: list[tuple[dict[str, str], dict[str, str]]] = []
    for barcode in sorted(resolution_by_barcode):
        resolution = resolution_by_barcode[barcode]
        mapping = mapping_by_barcode[barcode]
        if mapping["resolution_record_sha256"] != resolution["resolution_record_sha256"]:
            raise PromotionReadinessValidationError(
                f"Mapping provenance does not match resolution for barcode {barcode}"
            )
        joined.append((resolution, mapping))
    return joined


def _load_contract_vocabularies(path: Path) -> dict[str, Any]:
    try:
        vocabularies = catalog_tool._load_vocabularies(path)  # noqa: SLF001
    except catalog_tool.CatalogToolError as error:
        raise PromotionReadinessToolError(str(error)) from error

    required_values = {
        "unit_types": UNIT_TYPE,
        "sources": SOURCE,
        "verification_statuses": VERIFICATION_STATUS,
    }
    for vocabulary_name, value in required_values.items():
        if value not in vocabularies[vocabulary_name]:
            raise PromotionReadinessToolError(
                f"A2.2 requires {value!r} in P1.2 vocabulary {vocabulary_name}"
            )
    try:
        confidence = Decimal(TECHNICAL_CONFIDENCE_SCORE_V1)
    except InvalidOperation as error:
        raise PromotionReadinessToolError(
            "A2.2 technical confidence is not a valid decimal"
        ) from error
    if confidence < 0 or confidence > 1:
        raise PromotionReadinessToolError(
            "A2.2 technical confidence is outside the P1.2 range"
        )
    return vocabularies


def _select_name(row: dict[str, str]) -> str:
    return _trim(row["candidate_name_if_known"]) or _trim(row["off_product_name"])


def _select_brand(row: dict[str, str]) -> str:
    return _trim(row["candidate_brand_if_known"]) or _trim(row["off_brands"])


def _provenance_is_valid(row: dict[str, str], vocabularies: dict[str, Any]) -> bool:
    barcode = row["barcode"]
    barcode_type = row["barcode_type"]
    return all(
        (
            barcode == _trim(barcode),
            barcode_type in vocabularies["barcode_types"],
            catalog_tool.validate_barcode_shape(barcode, barcode_type) is None,
            row["source_match_status"] == "matched",
            bool(_trim(row["candidate_source_reference"])),
            bool(_trim(row["rights_reference"])),
            row["rights_class"] == "open_dataset_odbl_share_alike",
            bool(SHA256_RE.fullmatch(row["candidate_source_content_sha256"])),
            bool(SHA256_RE.fullmatch(row["off_source_content_sha256"])),
            bool(_trim(row["retrieved_at"])),
        )
    )


def _technical_row(
    resolution: dict[str, str], mapping: dict[str, str], name: str, brand: str
) -> dict[str, str]:
    row = {
        "primary_barcode": resolution["barcode"],
        "barcode_type": resolution["barcode_type"],
        "name": name,
        "brand": brand,
        "category_name": mapping["cronos_category_candidate"],
        "package_size": "",
        "package_unit": "",
        "unit_type": UNIT_TYPE,
        "source": SOURCE,
        "verification_status": VERIFICATION_STATUS,
        "confidence_score": TECHNICAL_CONFIDENCE_SCORE_V1,
        "source_reference": resolution["candidate_source_reference"],
        "rights_class": resolution["rights_class"],
        "rights_reference": resolution["rights_reference"],
        "resolution_record_sha256": resolution["resolution_record_sha256"],
        "category_mapping_record_sha256": mapping["category_mapping_record_sha256"],
        "readiness_record_sha256": "",
    }
    row["readiness_record_sha256"] = _expected_hash(
        row, TECHNICAL_READY_HEADERS, "readiness_record_sha256"
    )
    return row


def _blocked_row(
    resolution: dict[str, str],
    mapping: dict[str, str],
    *,
    name: str,
    reason: str,
) -> dict[str, str]:
    return {
        "barcode": resolution["barcode"],
        "technical_status": "blocked",
        "technical_reason": reason,
        "mapping_status": mapping["mapping_status"],
        "has_name": str(bool(name)).lower(),
        "has_category": str(bool(mapping["cronos_category_candidate"])).lower(),
        "rights_class": resolution["rights_class"],
        "resolution_record_sha256": resolution["resolution_record_sha256"],
        "category_mapping_record_sha256": mapping["category_mapping_record_sha256"],
    }


def _classify(
    joined: Sequence[tuple[dict[str, str], dict[str, str]]],
    vocabularies: dict[str, Any],
) -> tuple[list[dict[str, str]], list[dict[str, str]], list[dict[str, str]]]:
    technical_rows: list[dict[str, str]] = []
    master_rows: list[dict[str, str]] = []
    blocked_rows: list[dict[str, str]] = []

    for resolution, mapping in joined:
        name = _select_name(resolution)
        brand = _select_brand(resolution)
        if not _provenance_is_valid(resolution, vocabularies):
            reason = "invalid_input_provenance"
        elif mapping["mapping_status"] != "mapped":
            reason = "category_not_mapped"
        elif not name:
            reason = "missing_name"
        else:
            technical = _technical_row(resolution, mapping, name, brand)
            technical_rows.append(technical)
            rights_status = RIGHTS_STATUS_BY_CLASS.get(resolution["rights_class"])
            if rights_status == "promotion_compatible":
                master_rows.append(
                    {
                        **technical,
                        "promotion_rights_status": rights_status,
                        "promotion_reason": PROMOTION_REASON,
                    }
                )
            continue
        blocked_rows.append(
            _blocked_row(resolution, mapping, name=name, reason=reason)
        )

    return technical_rows, master_rows, blocked_rows


def _metric_slug(category: str) -> str:
    return category_mapping._metric_slug(category)  # noqa: SLF001


def _build_metrics(
    joined: Sequence[tuple[dict[str, str], dict[str, str]]],
    technical_rows: Sequence[dict[str, str]],
    master_rows: Sequence[dict[str, str]],
    blocked_rows: Sequence[dict[str, str]],
    categories: Sequence[str],
) -> dict[str, Any]:
    selected_names = [_select_name(resolution) for resolution, _ in joined]
    rights_statuses = [
        RIGHTS_STATUS_BY_CLASS.get(row["rights_class"]) for row in technical_rows
    ]
    metrics: dict[str, Any] = {
        "input_rows": len(joined),
        "category_mapped": sum(
            mapping["mapping_status"] == "mapped" for _, mapping in joined
        ),
        "category_not_mapped": sum(
            mapping["mapping_status"] != "mapped" for _, mapping in joined
        ),
        "with_name": sum(bool(name) for name in selected_names),
        "missing_name": sum(not name for name in selected_names),
        "technical_ready": len(technical_rows),
        "technical_blocked": len(blocked_rows),
        "technical_ready_with_brand": sum(bool(row["brand"]) for row in technical_rows),
        "technical_ready_without_brand": sum(not row["brand"] for row in technical_rows),
        "rights_odbl_sidecar_only": rights_statuses.count("odbl_sidecar_only"),
        "rights_promotion_compatible": rights_statuses.count("promotion_compatible"),
        "master_promotion_ready": len(master_rows),
        "master_promotion_blocked_rights": sum(
            RIGHTS_STATUS_BY_CLASS.get(row["rights_class"]) != "promotion_compatible"
            for row in technical_rows
        ),
        "unit_type_unidad": sum(row["unit_type"] == UNIT_TYPE for row in technical_rows),
        "readiness_contract_version": READINESS_CONTRACT_VERSION,
        "technical_confidence_score": TECHNICAL_CONFIDENCE_SCORE_V1,
        "network_access": False,
        "database_access": False,
        "uuid_generation": False,
    }
    for category in categories:
        metrics[f"technical_ready_{_metric_slug(category)}"] = sum(
            row["category_name"] == category for row in technical_rows
        )
    return metrics


def _write_csv(path: Path, headers: Sequence[str], rows: Sequence[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def _read_generated_csv(path: Path, headers: Sequence[str], output_name: str) -> list[dict[str, str]]:
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle, strict=True)
            if reader.fieldnames != list(headers):
                raise PromotionReadinessValidationError(
                    f"{output_name} header is invalid"
                )
            rows = list(reader)
    except (OSError, UnicodeError, csv.Error) as error:
        raise PromotionReadinessValidationError(
            f"Cannot validate {output_name}: {error}"
        ) from error
    return rows


def _validate_technical_output(
    path: Path,
    expected_rows: Sequence[dict[str, str]],
    vocabularies: dict[str, Any],
) -> None:
    rows = _read_generated_csv(path, TECHNICAL_READY_HEADERS, "technical-ready output")
    if rows != list(expected_rows):
        raise PromotionReadinessValidationError("Technical-ready output differs from its build")
    barcodes = [row["primary_barcode"] for row in rows]
    if barcodes != sorted(set(barcodes)):
        raise PromotionReadinessValidationError("Technical-ready output is not unique and sorted")
    for row_number, row in enumerate(rows, start=2):
        if not row["name"] or row["category_name"] not in vocabularies["categories"]:
            raise PromotionReadinessValidationError(
                f"Technical-ready row {row_number} lacks required catalog data"
            )
        if (
            row["barcode_type"] not in vocabularies["barcode_types"]
            or catalog_tool.validate_barcode_shape(
                row["primary_barcode"], row["barcode_type"]
            )
            is not None
        ):
            raise PromotionReadinessValidationError(
                f"Technical-ready row {row_number} has an invalid barcode contract"
            )
        if row["package_size"] or row["package_unit"]:
            raise PromotionReadinessValidationError(
                f"Technical-ready row {row_number} inferred package data"
            )
        if (
            row["unit_type"] != UNIT_TYPE
            or row["source"] != SOURCE
            or row["verification_status"] != VERIFICATION_STATUS
            or row["confidence_score"] != TECHNICAL_CONFIDENCE_SCORE_V1
            or not row["source_reference"]
            or row["rights_class"] not in RIGHTS_STATUS_BY_CLASS
            or not row["rights_reference"]
        ):
            raise PromotionReadinessValidationError(
                f"Technical-ready row {row_number} violates the readiness contract"
            )
        for hash_field in (
            "resolution_record_sha256",
            "category_mapping_record_sha256",
            "readiness_record_sha256",
        ):
            if not SHA256_RE.fullmatch(row[hash_field]):
                raise PromotionReadinessValidationError(
                    f"Technical-ready row {row_number} has invalid {hash_field}"
                )
        if row["readiness_record_sha256"] != _expected_hash(
            row, TECHNICAL_READY_HEADERS, "readiness_record_sha256"
        ):
            raise PromotionReadinessValidationError(
                f"Technical-ready row {row_number} has an inconsistent readiness hash"
            )


def _validate_master_output(
    path: Path, expected_rows: Sequence[dict[str, str]]
) -> None:
    rows = _read_generated_csv(path, MASTER_PROMOTION_HEADERS, "master-ready output")
    if rows != list(expected_rows):
        raise PromotionReadinessValidationError("Master-ready output differs from its build")
    barcodes = [row["primary_barcode"] for row in rows]
    if barcodes != sorted(set(barcodes)):
        raise PromotionReadinessValidationError("Master-ready output is not unique and sorted")
    for row_number, row in enumerate(rows, start=2):
        if (
            row["promotion_rights_status"] != "promotion_compatible"
            or row["promotion_reason"] != PROMOTION_REASON
        ):
            raise PromotionReadinessValidationError(
                f"Master-ready row {row_number} lacks promotion-compatible rights"
            )


def _validate_blocked_output(
    path: Path, expected_rows: Sequence[dict[str, str]]
) -> None:
    rows = _read_generated_csv(path, BLOCKED_HEADERS, "blocked output")
    if rows != list(expected_rows):
        raise PromotionReadinessValidationError("Blocked output differs from its build")
    barcodes = [row["barcode"] for row in rows]
    if barcodes != sorted(set(barcodes)):
        raise PromotionReadinessValidationError("Blocked output is not unique and sorted")
    for row_number, row in enumerate(rows, start=2):
        if row["technical_status"] != "blocked" or row["technical_reason"] not in TECHNICAL_REASONS:
            raise PromotionReadinessValidationError(
                f"Blocked row {row_number} has an invalid status or reason"
            )
        if row["mapping_status"] not in category_mapping.MAPPING_STATUSES:
            raise PromotionReadinessValidationError(
                f"Blocked row {row_number} has an invalid mapping_status"
            )
        if row["has_name"] not in {"true", "false"} or row["has_category"] not in {
            "true",
            "false",
        }:
            raise PromotionReadinessValidationError(
                f"Blocked row {row_number} has invalid boolean evidence"
            )


def _validate_metrics_output(path: Path, expected: dict[str, Any]) -> None:
    try:
        actual = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise PromotionReadinessValidationError(f"Cannot validate metrics output: {error}") from error
    if actual != expected:
        raise PromotionReadinessValidationError("Metrics output differs from its build")
    if actual["technical_ready"] + actual["technical_blocked"] != actual["input_rows"]:
        raise PromotionReadinessValidationError("Metrics do not reconcile input rows")


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


def build_readiness(
    *,
    resolution_path: Path,
    mapping_path: Path,
    technical_ready_path: Path,
    master_ready_path: Path,
    blocked_path: Path,
    metrics_path: Path,
    vocabularies_path: Path = catalog_tool.DEFAULT_CONFIG,
) -> dict[str, Any]:
    resolution_path = Path(resolution_path).expanduser().resolve()
    mapping_path = Path(mapping_path).expanduser().resolve()
    output_paths = [
        Path(path).expanduser().resolve()
        for path in (technical_ready_path, master_ready_path, blocked_path, metrics_path)
    ]
    technical_ready_path, master_ready_path, blocked_path, metrics_path = output_paths
    if len(set(output_paths)) != len(output_paths):
        raise PromotionReadinessToolError("A2.2 output paths must be distinct")
    if any(path in {resolution_path, mapping_path} for path in output_paths):
        raise PromotionReadinessToolError("A2.2 outputs must not overwrite inputs")

    vocabularies = _load_contract_vocabularies(Path(vocabularies_path).resolve())
    categories = list(vocabularies["categories"])
    joined = _load_inputs(resolution_path, mapping_path, categories)
    technical_rows, master_rows, blocked_rows = _classify(joined, vocabularies)
    metrics = _build_metrics(
        joined, technical_rows, master_rows, blocked_rows, categories
    )

    finals = [technical_ready_path, master_ready_path, blocked_path, metrics_path]
    temporary_pairs: list[tuple[Path, Path]] = []
    try:
        for final_path in finals:
            temporary_pairs.append((final_path, _temporary_output(final_path)))
        technical_temp, master_temp, blocked_temp, metrics_temp = [
            temporary for _, temporary in temporary_pairs
        ]
        _write_csv(technical_temp, TECHNICAL_READY_HEADERS, technical_rows)
        _write_csv(master_temp, MASTER_PROMOTION_HEADERS, master_rows)
        _write_csv(blocked_temp, BLOCKED_HEADERS, blocked_rows)
        metrics_temp.write_text(
            json.dumps(metrics, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
            encoding="utf-8",
        )

        _validate_technical_output(technical_temp, technical_rows, vocabularies)
        _validate_master_output(master_temp, master_rows)
        _validate_blocked_output(blocked_temp, blocked_rows)
        _validate_metrics_output(metrics_temp, metrics)

        for final_path, temporary_path in temporary_pairs:
            os.replace(temporary_path, final_path)
    finally:
        for _, temporary_path in temporary_pairs:
            try:
                temporary_path.unlink(missing_ok=True)
            except OSError:
                pass
    return metrics


def human_report(metrics: dict[str, Any], categories: Sequence[str]) -> str:
    lines = [
        "Promotion Readiness: SUCCESS",
        "",
        f"Input rows: {metrics['input_rows']}",
        "",
        f"Category mapped: {metrics['category_mapped']}",
        f"Technical ready: {metrics['technical_ready']}",
        f"Technical blocked: {metrics['technical_blocked']}",
        "",
        "Technical ready:",
    ]
    lines.extend(
        f"  {category}: {metrics[f'technical_ready_{_metric_slug(category)}']}"
        for category in categories
    )
    lines.extend(
        [
            "",
            f"ODbL sidecar only: {metrics['rights_odbl_sidecar_only']}",
            f"Master promotion ready: {metrics['master_promotion_ready']}",
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
    build = subparsers.add_parser("build", help="Build A2.2 readiness subsets")
    build.add_argument("--resolution", required=True, type=_path)
    build.add_argument("--mapping", required=True, type=_path)
    build.add_argument("--technical-ready", required=True, type=_path)
    build.add_argument("--master-ready", required=True, type=_path)
    build.add_argument("--blocked", required=True, type=_path)
    build.add_argument("--metrics", required=True, type=_path)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        metrics = build_readiness(
            resolution_path=args.resolution,
            mapping_path=args.mapping,
            technical_ready_path=args.technical_ready,
            master_ready_path=args.master_ready,
            blocked_path=args.blocked,
            metrics_path=args.metrics,
        )
        vocabularies = _load_contract_vocabularies(catalog_tool.DEFAULT_CONFIG)
        print(human_report(metrics, vocabularies["categories"]))
        return 0
    except PromotionReadinessValidationError as error:
        print(f"VALIDATION ERROR: {error}", file=sys.stderr)
        return 1
    except (PromotionReadinessToolError, OSError) as error:
        print(f"TOOL ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
