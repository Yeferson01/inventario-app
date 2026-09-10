#!/usr/bin/env python3
"""Build an auditable A2.3 provisional master-seed materialization."""

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
from resolution import category_mapping  # noqa: E402
from resolution import promotion_readiness  # noqa: E402


PROVENANCE_HEADERS = [
    "primary_barcode",
    "materialization_mode",
    "source",
    "source_reference",
    "rights_class",
    "rights_reference",
    "resolution_record_sha256",
    "category_mapping_record_sha256",
    "readiness_record_sha256",
    "materialization_record_sha256",
]

CONFLICT_HEADERS = [
    "primary_barcode",
    "reason_code",
    "existing_seed_present",
    "incoming_name",
    "incoming_category_name",
    "incoming_source_reference",
]

MATERIALIZATION_MODE = "provisional_open_dataset_override"
CONFLICT_REASON = "barcode_already_in_existing_seed"
EXPECTED_RIGHTS_CLASS = "open_dataset_odbl_share_alike"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
CSV_FIELD_SIZE_LIMIT = 64 * 1024 * 1024


class MasterSeedMaterializerToolError(Exception):
    """Usage, I/O, or configuration error (exit code 2)."""


class MasterSeedMaterializerValidationError(Exception):
    """Invalid input or generated output (exit code 1)."""


def _path(value: str) -> Path:
    return Path(value).expanduser().resolve()


def _read_technical_ready(path: Path) -> list[dict[str, str]]:
    csv.field_size_limit(CSV_FIELD_SIZE_LIMIT)
    try:
        handle = path.open("r", encoding="utf-8-sig", newline="")
    except OSError as error:
        raise MasterSeedMaterializerToolError(
            f"Cannot read technical-ready input {path}: {error}"
        ) from error

    rows: list[dict[str, str]] = []
    seen_barcodes: set[str] = set()
    try:
        with handle:
            reader = csv.reader(handle, strict=True)
            try:
                actual_headers = next(reader)
            except StopIteration as error:
                raise MasterSeedMaterializerValidationError(
                    "Technical-ready input is empty and has no header"
                ) from error
            if actual_headers != promotion_readiness.TECHNICAL_READY_HEADERS:
                raise MasterSeedMaterializerValidationError(
                    "Technical-ready input header is incompatible with A2.2"
                )
            for row_number, raw_row in enumerate(reader, start=2):
                if len(raw_row) != len(actual_headers):
                    raise MasterSeedMaterializerValidationError(
                        f"Technical-ready row {row_number} has an invalid field count"
                    )
                row = dict(zip(actual_headers, raw_row, strict=True))
                barcode = row["primary_barcode"]
                if not barcode:
                    raise MasterSeedMaterializerValidationError(
                        f"Technical-ready row {row_number} has an empty barcode"
                    )
                if barcode in seen_barcodes:
                    raise MasterSeedMaterializerValidationError(
                        f"Duplicate technical-ready barcode: {barcode}"
                    )
                seen_barcodes.add(barcode)
                rows.append(row)
    except (csv.Error, UnicodeError) as error:
        raise MasterSeedMaterializerValidationError(
            f"Cannot parse technical-ready input: {error}"
        ) from error
    return rows


def _load_vocabularies(path: Path) -> dict[str, Any]:
    try:
        vocabularies = catalog_tool._load_vocabularies(path)  # noqa: SLF001
    except catalog_tool.CatalogToolError as error:
        raise MasterSeedMaterializerToolError(str(error)) from error

    requirements = {
        "unit_types": promotion_readiness.UNIT_TYPE,
        "sources": promotion_readiness.SOURCE,
        "verification_statuses": promotion_readiness.VERIFICATION_STATUS,
        "barcode_types": "gtin",
    }
    for vocabulary_name, required_value in requirements.items():
        if required_value not in vocabularies[vocabulary_name]:
            raise MasterSeedMaterializerToolError(
                f"A2.3 requires {required_value!r} in P1.2 vocabulary {vocabulary_name}"
            )
    return vocabularies


def _expected_readiness_hash(row: dict[str, str]) -> str:
    return catalog_tool.record_hash(
        {
            header: row[header]
            for header in promotion_readiness.TECHNICAL_READY_HEADERS
            if header != "readiness_record_sha256"
        }
    )


def _validate_technical_rows(
    rows: Sequence[dict[str, str]], vocabularies: dict[str, Any]
) -> None:
    for row_number, row in enumerate(rows, start=2):
        barcode = row["primary_barcode"]
        barcode_type = row["barcode_type"]
        if barcode != catalog_tool.normalize_visible_text(barcode):
            raise MasterSeedMaterializerValidationError(
                f"Technical-ready row {row_number} has a non-canonical barcode"
            )
        if barcode_type not in vocabularies["barcode_types"]:
            raise MasterSeedMaterializerValidationError(
                f"Technical-ready row {row_number} has an invalid barcode_type"
            )
        barcode_error = catalog_tool.validate_barcode_shape(barcode, barcode_type)
        if barcode_error:
            raise MasterSeedMaterializerValidationError(
                f"Technical-ready row {row_number} has an invalid barcode: {barcode_error}"
            )
        if not catalog_tool.normalize_visible_text(row["name"]):
            raise MasterSeedMaterializerValidationError(
                f"Technical-ready row {row_number} has an empty name"
            )
        if row["category_name"] not in vocabularies["categories"]:
            raise MasterSeedMaterializerValidationError(
                f"Technical-ready row {row_number} has an invalid category_name"
            )
        if row["unit_type"] not in vocabularies["unit_types"]:
            raise MasterSeedMaterializerValidationError(
                f"Technical-ready row {row_number} has an invalid unit_type"
            )
        if row["source"] not in vocabularies["sources"]:
            raise MasterSeedMaterializerValidationError(
                f"Technical-ready row {row_number} has an invalid source"
            )
        if row["verification_status"] not in vocabularies["verification_statuses"]:
            raise MasterSeedMaterializerValidationError(
                f"Technical-ready row {row_number} has an invalid verification_status"
            )
        try:
            confidence = Decimal(row["confidence_score"])
        except InvalidOperation as error:
            raise MasterSeedMaterializerValidationError(
                f"Technical-ready row {row_number} has an invalid confidence_score"
            ) from error
        if (
            not row["confidence_score"]
            or catalog_tool.SCIENTIFIC_NOTATION_RE.fullmatch(row["confidence_score"])
            or not catalog_tool.DECIMAL_RE.fullmatch(row["confidence_score"])
            or confidence < 0
            or confidence > 1
        ):
            raise MasterSeedMaterializerValidationError(
                f"Technical-ready row {row_number} has an invalid confidence_score"
            )
        if row["package_size"] or row["package_unit"]:
            raise MasterSeedMaterializerValidationError(
                f"Technical-ready row {row_number} is not an A2.2 unit-only record"
            )
        if (
            row["unit_type"] != promotion_readiness.UNIT_TYPE
            or row["source"] != promotion_readiness.SOURCE
            or row["verification_status"] != promotion_readiness.VERIFICATION_STATUS
            or row["confidence_score"]
            != promotion_readiness.TECHNICAL_CONFIDENCE_SCORE_V1
            or row["rights_class"] != EXPECTED_RIGHTS_CLASS
        ):
            raise MasterSeedMaterializerValidationError(
                f"Technical-ready row {row_number} is outside the A2.3 provisional contract"
            )
        for required_field in (
            "source_reference",
            "rights_class",
            "rights_reference",
        ):
            if not catalog_tool.normalize_visible_text(row[required_field]):
                raise MasterSeedMaterializerValidationError(
                    f"Technical-ready row {row_number} has an empty {required_field}"
                )
        for hash_field in (
            "resolution_record_sha256",
            "category_mapping_record_sha256",
            "readiness_record_sha256",
        ):
            if not SHA256_RE.fullmatch(row[hash_field]):
                raise MasterSeedMaterializerValidationError(
                    f"Technical-ready row {row_number} has an invalid {hash_field}"
                )
        if row["readiness_record_sha256"] != _expected_readiness_hash(row):
            raise MasterSeedMaterializerValidationError(
                f"Technical-ready row {row_number} has an inconsistent readiness hash"
            )


def _read_existing_seed_barcodes(path: Path) -> tuple[int, set[str]]:
    csv.field_size_limit(CSV_FIELD_SIZE_LIMIT)
    try:
        handle = path.open("r", encoding="utf-8-sig", newline="")
    except OSError as error:
        raise MasterSeedMaterializerToolError(
            f"Cannot read existing seed {path}: {error}"
        ) from error

    existing_rows = 0
    barcodes: set[str] = set()
    try:
        with handle:
            reader = csv.reader(handle, strict=True)
            try:
                headers = next(reader)
            except StopIteration as error:
                raise MasterSeedMaterializerValidationError(
                    "Existing seed is empty and has no header"
                ) from error
            if (
                not headers
                or any(not header for header in headers)
                or len(set(headers)) != len(headers)
                or "primary_barcode" not in headers
            ):
                raise MasterSeedMaterializerValidationError(
                    "Existing seed header does not expose a unique primary_barcode column"
                )
            barcode_index = headers.index("primary_barcode")
            for row_number, raw_row in enumerate(reader, start=2):
                if not any(catalog_tool.normalize_visible_text(value) for value in raw_row):
                    continue
                existing_rows += 1
                if barcode_index >= len(raw_row):
                    raise MasterSeedMaterializerValidationError(
                        f"Existing seed row {row_number} does not expose primary_barcode"
                    )
                raw_barcode = raw_row[barcode_index]
                barcode = catalog_tool.normalize_barcode(raw_barcode)
                if barcode:
                    barcodes.add(barcode)
    except (csv.Error, UnicodeError) as error:
        raise MasterSeedMaterializerValidationError(
            f"Cannot parse existing seed safely: {error}"
        ) from error
    return existing_rows, barcodes


def _master_row(technical: dict[str, str]) -> dict[str, str]:
    return {
        "master_product_id": "",
        "primary_barcode": technical["primary_barcode"],
        "barcode_type": technical["barcode_type"],
        "name": technical["name"],
        "brand": technical["brand"],
        "manufacturer": "",
        "category_name": technical["category_name"],
        "subcategory_name": "",
        "package_size": "",
        "package_unit": "",
        "unit_type": technical["unit_type"],
        "description": "",
        "source": technical["source"],
        "verification_status": technical["verification_status"],
        "confidence_score": technical["confidence_score"],
        "source_reference": technical["source_reference"],
        "image_source_key": "",
        "image_license": "",
        "image_attribution": "",
    }


def _provenance_without_materialization_hash(
    technical: dict[str, str]
) -> dict[str, str]:
    return {
        "primary_barcode": technical["primary_barcode"],
        "materialization_mode": MATERIALIZATION_MODE,
        "source": technical["source"],
        "source_reference": technical["source_reference"],
        "rights_class": technical["rights_class"],
        "rights_reference": technical["rights_reference"],
        "resolution_record_sha256": technical["resolution_record_sha256"],
        "category_mapping_record_sha256": technical[
            "category_mapping_record_sha256"
        ],
        "readiness_record_sha256": technical["readiness_record_sha256"],
    }


def materialization_record_hash(
    master_row: dict[str, str], provenance_without_hash: dict[str, str]
) -> str:
    """Hash the complete master row and the factual A2.3 provenance."""
    barcode = master_row["primary_barcode"]
    return catalog_tool.record_hash(
        {
            "primary_barcode": barcode,
            "master_row": {
                header: master_row[header] for header in catalog_tool.MASTER_HEADERS
            },
            "provenance": {
                header: provenance_without_hash[header]
                for header in PROVENANCE_HEADERS
                if header != "materialization_record_sha256"
            },
            "materialization_mode": MATERIALIZATION_MODE,
        }
    )


def _provenance_row(
    technical: dict[str, str], master_row: dict[str, str]
) -> dict[str, str]:
    row = _provenance_without_materialization_hash(technical)
    row["materialization_record_sha256"] = materialization_record_hash(
        master_row, row
    )
    return row


def _conflict_row(technical: dict[str, str]) -> dict[str, str]:
    return {
        "primary_barcode": technical["primary_barcode"],
        "reason_code": CONFLICT_REASON,
        "existing_seed_present": "true",
        "incoming_name": technical["name"],
        "incoming_category_name": technical["category_name"],
        "incoming_source_reference": technical["source_reference"],
    }


def _materialize(
    technical_rows: Sequence[dict[str, str]], existing_barcodes: set[str]
) -> tuple[list[dict[str, str]], list[dict[str, str]], list[dict[str, str]]]:
    master_rows: list[dict[str, str]] = []
    provenance_rows: list[dict[str, str]] = []
    conflict_rows: list[dict[str, str]] = []
    for technical in sorted(technical_rows, key=lambda row: row["primary_barcode"]):
        barcode = technical["primary_barcode"]
        if barcode in existing_barcodes:
            conflict_rows.append(_conflict_row(technical))
            continue
        master = _master_row(technical)
        master_rows.append(master)
        provenance_rows.append(_provenance_row(technical, master))
    return master_rows, provenance_rows, conflict_rows


def _metric_slug(category: str) -> str:
    return category_mapping._metric_slug(category)  # noqa: SLF001


def _build_metrics(
    technical_rows: Sequence[dict[str, str]],
    existing_rows: int,
    existing_barcodes: set[str],
    master_rows: Sequence[dict[str, str]],
    provenance_rows: Sequence[dict[str, str]],
    conflict_rows: Sequence[dict[str, str]],
    categories: Sequence[str],
) -> dict[str, Any]:
    metrics: dict[str, Any] = {
        "technical_ready_input": len(technical_rows),
        "existing_seed_rows": existing_rows,
        "existing_seed_unique_barcodes": len(existing_barcodes),
        "provisional_master_rows": len(master_rows),
        "provenance_rows": len(provenance_rows),
        "barcode_conflicts_existing_seed": len(conflict_rows),
        "with_brand": sum(bool(row["brand"]) for row in master_rows),
        "without_brand": sum(not row["brand"] for row in master_rows),
        "ean13": sum(row["barcode_type"] == "ean13" for row in master_rows),
        "ean8": sum(row["barcode_type"] == "ean8" for row in master_rows),
        "upc": sum(row["barcode_type"] == "upc" for row in master_rows),
        "gtin14": sum(row["barcode_type"] == "gtin" for row in master_rows),
        "source_open_dataset": sum(
            row["source"] == "open_dataset" for row in master_rows
        ),
        "verification_unverified": sum(
            row["verification_status"] == "unverified" for row in master_rows
        ),
        "unit_type_unidad": sum(
            row["unit_type"] == "unidad" for row in master_rows
        ),
        "provisional_override_used": True,
        "uuid_generation": False,
        "database_access": False,
        "network_access": False,
    }
    for category in categories:
        metrics[_metric_slug(category)] = sum(
            row["category_name"] == category for row in master_rows
        )
    return metrics


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


def _write_csv(
    path: Path, headers: Sequence[str], rows: Sequence[dict[str, str]]
) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def _read_generated_csv(
    path: Path, headers: Sequence[str], output_name: str
) -> list[dict[str, str]]:
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle, strict=True)
            if reader.fieldnames != list(headers):
                raise MasterSeedMaterializerValidationError(
                    f"{output_name} header is invalid"
                )
            rows = list(reader)
    except (OSError, UnicodeError, csv.Error) as error:
        raise MasterSeedMaterializerValidationError(
            f"Cannot validate {output_name}: {error}"
        ) from error
    if any(None in row for row in rows):
        raise MasterSeedMaterializerValidationError(
            f"{output_name} contains an invalid field count"
        )
    return rows


def _validate_master_output(
    path: Path,
    expected_rows: Sequence[dict[str, str]],
    vocabularies: dict[str, Any],
) -> list[dict[str, str]]:
    rows = _read_generated_csv(path, catalog_tool.MASTER_HEADERS, "master output")
    if rows != list(expected_rows):
        raise MasterSeedMaterializerValidationError(
            "Master output differs from its deterministic build"
        )
    barcodes = [row["primary_barcode"] for row in rows]
    if barcodes != sorted(set(barcodes)):
        raise MasterSeedMaterializerValidationError(
            "Master output is not unique and sorted"
        )
    required_without_id = set(catalog_tool.REQUIRED_MASTER_FIELDS) - {
        "master_product_id"
    }
    for row_number, row in enumerate(rows, start=2):
        if row["master_product_id"]:
            raise MasterSeedMaterializerValidationError(
                f"Master row {row_number} generated a master_product_id"
            )
        if any(not row[field] for field in required_without_id):
            raise MasterSeedMaterializerValidationError(
                f"Master row {row_number} lacks required P1.2 fields"
            )
        if row["package_size"] or row["package_unit"]:
            raise MasterSeedMaterializerValidationError(
                f"Master row {row_number} inferred package data"
            )
        issues: list[catalog_tool.Issue] = []
        catalog_tool._normalize_master(  # noqa: SLF001
            {**row, "__row_number__": str(row_number)},
            vocabularies,
            path.name,
            issues,
        )
        unexpected_issues = [
            issue
            for issue in issues
            if not (
                issue.code == "missing_required_field"
                and issue.field == "master_product_id"
            )
        ]
        if unexpected_issues:
            raise MasterSeedMaterializerValidationError(
                f"Master row {row_number} violates P1.2: {unexpected_issues[0].message}"
            )
    return rows


def _validate_provenance_output(
    path: Path,
    expected_rows: Sequence[dict[str, str]],
    master_rows: Sequence[dict[str, str]],
) -> list[dict[str, str]]:
    rows = _read_generated_csv(path, PROVENANCE_HEADERS, "provenance output")
    if rows != list(expected_rows):
        raise MasterSeedMaterializerValidationError(
            "Provenance output differs from its deterministic build"
        )
    barcodes = [row["primary_barcode"] for row in rows]
    master_by_barcode = {row["primary_barcode"]: row for row in master_rows}
    if barcodes != sorted(set(barcodes)) or set(barcodes) != set(master_by_barcode):
        raise MasterSeedMaterializerValidationError(
            "Master and provenance barcode sets are not identical and unique"
        )
    for row_number, row in enumerate(rows, start=2):
        if (
            row["materialization_mode"] != MATERIALIZATION_MODE
            or row["source"] != promotion_readiness.SOURCE
            or row["rights_class"] != EXPECTED_RIGHTS_CLASS
            or not row["source_reference"]
            or not row["rights_reference"]
        ):
            raise MasterSeedMaterializerValidationError(
                f"Provenance row {row_number} violates the A2.3 contract"
            )
        for hash_field in (
            "resolution_record_sha256",
            "category_mapping_record_sha256",
            "readiness_record_sha256",
            "materialization_record_sha256",
        ):
            if not SHA256_RE.fullmatch(row[hash_field]):
                raise MasterSeedMaterializerValidationError(
                    f"Provenance row {row_number} has an invalid {hash_field}"
                )
        without_hash = {
            header: row[header]
            for header in PROVENANCE_HEADERS
            if header != "materialization_record_sha256"
        }
        expected_hash = materialization_record_hash(
            master_by_barcode[row["primary_barcode"]], without_hash
        )
        if row["materialization_record_sha256"] != expected_hash:
            raise MasterSeedMaterializerValidationError(
                f"Provenance row {row_number} has an inconsistent materialization hash"
            )
    return rows


def _validate_conflicts_output(
    path: Path,
    expected_rows: Sequence[dict[str, str]],
    master_rows: Sequence[dict[str, str]],
) -> list[dict[str, str]]:
    rows = _read_generated_csv(path, CONFLICT_HEADERS, "conflicts output")
    if rows != list(expected_rows):
        raise MasterSeedMaterializerValidationError(
            "Conflicts output differs from its deterministic build"
        )
    barcodes = [row["primary_barcode"] for row in rows]
    master_barcodes = {row["primary_barcode"] for row in master_rows}
    if barcodes != sorted(set(barcodes)) or master_barcodes.intersection(barcodes):
        raise MasterSeedMaterializerValidationError(
            "Conflicts are not unique, sorted, and separated from master rows"
        )
    for row_number, row in enumerate(rows, start=2):
        if (
            row["reason_code"] != CONFLICT_REASON
            or row["existing_seed_present"] != "true"
            or not row["primary_barcode"]
        ):
            raise MasterSeedMaterializerValidationError(
                f"Conflict row {row_number} violates the A2.3 contract"
            )
    return rows


def _validate_metrics_output(path: Path, expected: dict[str, Any]) -> None:
    try:
        actual = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise MasterSeedMaterializerValidationError(
            f"Cannot validate metrics output: {error}"
        ) from error
    if actual != expected:
        raise MasterSeedMaterializerValidationError(
            "Metrics output differs from its deterministic build"
        )
    if (
        actual["provisional_master_rows"] + actual["barcode_conflicts_existing_seed"]
        != actual["technical_ready_input"]
        or actual["provenance_rows"] != actual["provisional_master_rows"]
        or actual["with_brand"] + actual["without_brand"]
        != actual["provisional_master_rows"]
    ):
        raise MasterSeedMaterializerValidationError(
            "Materialization metrics do not reconcile"
        )


def build_materialization(
    *,
    technical_ready_path: Path,
    existing_seed_path: Path,
    output_path: Path,
    provenance_path: Path,
    conflicts_path: Path,
    metrics_path: Path,
    allow_provisional_open_dataset: bool,
    vocabularies_path: Path = catalog_tool.DEFAULT_CONFIG,
) -> dict[str, Any]:
    if not allow_provisional_open_dataset:
        raise MasterSeedMaterializerToolError(
            "A2.3 requires --allow-provisional-open-dataset"
        )

    technical_ready_path = Path(technical_ready_path).expanduser().resolve()
    existing_seed_path = Path(existing_seed_path).expanduser().resolve()
    output_paths = [
        Path(path).expanduser().resolve()
        for path in (output_path, provenance_path, conflicts_path, metrics_path)
    ]
    output_path, provenance_path, conflicts_path, metrics_path = output_paths
    if technical_ready_path == existing_seed_path:
        raise MasterSeedMaterializerToolError(
            "Technical-ready input and existing seed must be different files"
        )
    if len(set(output_paths)) != len(output_paths):
        raise MasterSeedMaterializerToolError("A2.3 output paths must be distinct")
    if any(path in {technical_ready_path, existing_seed_path} for path in output_paths):
        raise MasterSeedMaterializerToolError(
            "A2.3 outputs must not overwrite either input"
        )

    vocabularies = _load_vocabularies(Path(vocabularies_path).resolve())
    technical_rows = _read_technical_ready(technical_ready_path)
    _validate_technical_rows(technical_rows, vocabularies)
    existing_rows, existing_barcodes = _read_existing_seed_barcodes(
        existing_seed_path
    )
    master_rows, provenance_rows, conflict_rows = _materialize(
        technical_rows, existing_barcodes
    )
    categories = list(vocabularies["categories"])
    metrics = _build_metrics(
        technical_rows,
        existing_rows,
        existing_barcodes,
        master_rows,
        provenance_rows,
        conflict_rows,
        categories,
    )

    finals = [output_path, provenance_path, conflicts_path, metrics_path]
    temporary_pairs: list[tuple[Path, Path]] = []
    try:
        for final_path in finals:
            temporary_pairs.append((final_path, _temporary_output(final_path)))
        master_temp, provenance_temp, conflicts_temp, metrics_temp = [
            temporary for _, temporary in temporary_pairs
        ]
        _write_csv(master_temp, catalog_tool.MASTER_HEADERS, master_rows)
        _write_csv(provenance_temp, PROVENANCE_HEADERS, provenance_rows)
        _write_csv(conflicts_temp, CONFLICT_HEADERS, conflict_rows)
        metrics_temp.write_text(
            json.dumps(metrics, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
            encoding="utf-8",
        )

        validated_master_rows = _validate_master_output(
            master_temp, master_rows, vocabularies
        )
        _validate_provenance_output(
            provenance_temp, provenance_rows, validated_master_rows
        )
        _validate_conflicts_output(
            conflicts_temp, conflict_rows, validated_master_rows
        )
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
        "Master Seed Materialization: SUCCESS",
        "",
        f"Technical-ready input: {metrics['technical_ready_input']}",
        f"Existing seed barcodes: {metrics['existing_seed_unique_barcodes']}",
        "",
        f"Provisional master rows: {metrics['provisional_master_rows']}",
        f"Existing barcode conflicts: {metrics['barcode_conflicts_existing_seed']}",
        "",
        "Categories:",
    ]
    lines.extend(
        f"  {category}: {metrics[_metric_slug(category)]}" for category in categories
    )
    lines.extend(
        [
            "",
            "Materialization mode:",
            f"  {MATERIALIZATION_MODE}",
            "",
            "UUID generation: none",
            "Database access: none",
            "Network access: none",
        ]
    )
    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    build = subparsers.add_parser("build", help="Build A2.3 provisional outputs")
    build.add_argument("--technical-ready", required=True, type=_path)
    build.add_argument("--existing-seed", required=True, type=_path)
    build.add_argument("--output", required=True, type=_path)
    build.add_argument("--provenance", required=True, type=_path)
    build.add_argument("--conflicts", required=True, type=_path)
    build.add_argument("--metrics", required=True, type=_path)
    build.add_argument("--allow-provisional-open-dataset", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        metrics = build_materialization(
            technical_ready_path=args.technical_ready,
            existing_seed_path=args.existing_seed,
            output_path=args.output,
            provenance_path=args.provenance,
            conflicts_path=args.conflicts,
            metrics_path=args.metrics,
            allow_provisional_open_dataset=args.allow_provisional_open_dataset,
        )
        vocabularies = _load_vocabularies(catalog_tool.DEFAULT_CONFIG)
        print(human_report(metrics, vocabularies["categories"]))
        return 0
    except MasterSeedMaterializerValidationError as error:
        print(f"VALIDATION ERROR: {error}", file=sys.stderr)
        return 1
    except (MasterSeedMaterializerToolError, OSError) as error:
        print(f"TOOL ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
