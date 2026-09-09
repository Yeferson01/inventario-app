#!/usr/bin/env python3
"""Build a factual A2.0 resolution snapshot from A1 OFF candidates and an OFF dump."""

from __future__ import annotations

import argparse
import csv
import gzip
import json
import os
import re
import sys
import tempfile
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Sequence


CATALOG_IMPORT_DIR = Path(__file__).resolve().parents[1]
if str(CATALOG_IMPORT_DIR) not in sys.path:
    sys.path.insert(0, str(CATALOG_IMPORT_DIR))

import catalog_tool  # noqa: E402
from acquisition import candidate_tool  # noqa: E402


RESOLUTION_HEADERS = [
    "barcode",
    "barcode_type",
    "candidate_name_if_known",
    "candidate_brand_if_known",
    "off_product_name",
    "off_brands",
    "off_categories_tags",
    "off_main_category",
    "off_quantity",
    "off_last_modified_t",
    "name_status",
    "brand_status",
    "category_status",
    "quantity_status",
    "source_match_status",
    "off_source_row_count",
    "candidate_source_reference",
    "candidate_source_content_sha256",
    "off_source_content_sha256",
    "retrieved_at",
    "rights_class",
    "rights_reference",
    "resolution_record_sha256",
]

REQUIRED_OFF_HEADERS = [
    "code",
    "product_name",
    "brands",
    "categories_tags",
    "main_category",
    "quantity",
    "last_modified_t",
]

STATUS_VALUES = {"available", "missing", "conflict"}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
CANDIDATE_SHA256_RE = re.compile(r"^[0-9a-fA-F]{64}$")
CSV_FIELD_SIZE_LIMIT = 64 * 1024 * 1024


class ResolutionToolError(Exception):
    """Usage, I/O, or incompatible snapshot error (exit code 2)."""


class ResolutionValidationError(Exception):
    """Input or generated resolution content is invalid (exit code 1)."""


@dataclass
class OffAggregate:
    barcode: str
    source_row_count: int = 0
    source_hashes: list[str] = field(default_factory=list)
    product_names: dict[str, set[str]] = field(default_factory=dict)
    brands: dict[str, set[str]] = field(default_factory=dict)
    categories_tags: dict[str, set[str]] = field(default_factory=dict)
    main_categories: dict[str, set[str]] = field(default_factory=dict)
    quantities: dict[str, set[str]] = field(default_factory=dict)
    last_modified_values: dict[str, set[str]] = field(default_factory=dict)


def _path(value: str) -> Path:
    return Path(value).expanduser().resolve()


def _source_value(value: Any) -> str:
    """Apply NFC and exterior trim only; keep source wording and tag order."""
    text = "" if value is None else str(value)
    return unicodedata.normalize("NFC", text).strip()


def _add_value(target: dict[str, set[str]], raw_value: Any) -> None:
    display = _source_value(raw_value)
    if display:
        target.setdefault(display, set()).add(display)


def _resolve_value(values: dict[str, set[str]]) -> tuple[str, str]:
    if not values:
        return "", "missing"
    if len(values) > 1:
        return "", "conflict"
    displays = next(iter(values.values()))
    return sorted(displays)[0], "available"


def _load_candidates(path: Path) -> tuple[list[dict[str, str]], dict[str, Any]]:
    try:
        report = candidate_tool.validate_candidates(input_path=path)
    except (candidate_tool.CandidateToolError, catalog_tool.CatalogToolError) as error:
        raise ResolutionToolError(str(error)) from error
    if not report["valid"]:
        raise ResolutionValidationError(
            "Candidate input failed A1.1 validation: "
            + json.dumps(report["blocking_errors"], ensure_ascii=False)
        )

    try:
        handle = path.open("r", encoding="utf-8-sig", newline="")
    except OSError as error:
        raise ResolutionToolError(f"Cannot read candidate CSV {path}: {error}") from error
    with handle:
        try:
            reader = csv.DictReader(handle, strict=True)
            if reader.fieldnames != candidate_tool.CANDIDATE_HEADERS:
                raise ResolutionValidationError(
                    "Candidate header does not match candidate_tool.CANDIDATE_HEADERS"
                )
            rows = [
                {header: raw.get(header, "") or "" for header in candidate_tool.CANDIDATE_HEADERS}
                for raw in reader
                if any(raw.values())
            ]
        except (csv.Error, UnicodeError) as error:
            raise ResolutionToolError(f"Cannot parse candidate CSV {path}: {error}") from error

    for row_number, row in enumerate(rows, start=2):
        if (
            _source_value(row["source"]) != "open_dataset"
            or _source_value(row["source_channel"]) != "open_food_facts"
            or _source_value(row["rights_class"]) != "open_dataset_odbl_share_alike"
        ):
            raise ResolutionValidationError(
                f"Candidate row {row_number} is not an Open Food Facts ODbL candidate"
            )
    rows.sort(key=lambda row: row["barcode"])
    return rows, report


def _read_off_header(path: Path) -> list[str]:
    try:
        with gzip.open(path, "rt", encoding="utf-8-sig", newline="") as handle:
            reader = csv.reader(handle, delimiter="\t", strict=True)
            try:
                headers = next(reader)
            except StopIteration as error:
                raise ResolutionToolError("OFF snapshot is empty and has no header") from error
    except (OSError, EOFError, gzip.BadGzipFile, UnicodeError, csv.Error) as error:
        raise ResolutionToolError(f"Cannot read OFF snapshot header {path}: {error}") from error

    if any(not header for header in headers):
        raise ResolutionToolError("OFF snapshot header contains an empty column")
    if len(headers) != len(set(headers)):
        raise ResolutionToolError("OFF snapshot header contains duplicate columns")
    missing = [header for header in REQUIRED_OFF_HEADERS if header not in headers]
    if missing:
        raise ResolutionToolError(
            "OFF snapshot header is missing required columns: " + ", ".join(missing)
        )
    return headers


def _scan_off(
    path: Path,
    *,
    headers: list[str],
    candidate_barcodes: set[str],
    metrics: dict[str, Any],
) -> dict[str, OffAggregate]:
    """Scan logical records returned after the header.

    off_rows_scanned counts every returned logical record. A record contributes
    to off_malformed_csv_rows only when its field count differs from the header.
    """
    aggregates: dict[str, OffAggregate] = {}
    csv.field_size_limit(CSV_FIELD_SIZE_LIMIT)
    try:
        handle = gzip.open(path, "rt", encoding="utf-8-sig", newline="")
    except OSError as error:
        raise ResolutionToolError(f"Cannot open OFF snapshot {path}: {error}") from error

    try:
        with handle:
            reader = csv.reader(handle, delimiter="\t", strict=False)
            try:
                actual_headers = next(reader)
            except (StopIteration, csv.Error) as error:
                raise ResolutionToolError(f"Cannot parse OFF snapshot header: {error}") from error
            if actual_headers != headers:
                raise ResolutionToolError("OFF snapshot header changed between inspection and scan")

            while True:
                try:
                    raw_row = next(reader)
                except StopIteration:
                    break
                except csv.Error as error:
                    raise ResolutionToolError(
                        "Cannot safely continue after OFF CSV parser error near "
                        f"physical line {reader.line_num}: {error}"
                    ) from error
                metrics["off_rows_scanned"] += 1
                if len(raw_row) != len(headers):
                    metrics["off_malformed_csv_rows"] += 1
                    continue
                record = dict(zip(headers, raw_row, strict=True))
                barcode = record["code"].strip()
                if barcode not in candidate_barcodes:
                    continue

                metrics["off_candidate_rows_matched"] += 1
                aggregate = aggregates.get(barcode)
                if aggregate is None:
                    aggregate = OffAggregate(barcode=barcode)
                    aggregates[barcode] = aggregate
                else:
                    metrics["duplicate_off_rows"] += 1
                aggregate.source_row_count += 1
                aggregate.source_hashes.append(catalog_tool.record_hash(record))
                _add_value(aggregate.product_names, record["product_name"])
                _add_value(aggregate.brands, record["brands"])
                _add_value(aggregate.categories_tags, record["categories_tags"])
                _add_value(aggregate.main_categories, record["main_category"])
                _add_value(aggregate.quantities, record["quantity"])
                _add_value(aggregate.last_modified_values, record["last_modified_t"])
    except (OSError, EOFError, gzip.BadGzipFile, UnicodeError) as error:
        raise ResolutionToolError(f"Cannot read OFF snapshot {path}: {error}") from error
    return aggregates


def _category_result(aggregate: OffAggregate) -> tuple[str, str, str]:
    categories, categories_status = _resolve_value(aggregate.categories_tags)
    main_category, main_status = _resolve_value(aggregate.main_categories)
    if "conflict" in (categories_status, main_status):
        return categories, main_category, "conflict"
    if categories_status == "missing" and main_status == "missing":
        return "", "", "missing"
    return categories, main_category, "available"


def _resolution_row(candidate: dict[str, str], aggregate: OffAggregate) -> dict[str, str]:
    product_name, name_status = _resolve_value(aggregate.product_names)
    brands, brand_status = _resolve_value(aggregate.brands)
    categories_tags, main_category, category_status = _category_result(aggregate)
    quantity, quantity_status = _resolve_value(aggregate.quantities)
    last_modified, last_modified_status = _resolve_value(aggregate.last_modified_values)
    if last_modified_status == "conflict":
        last_modified = ""

    row = {
        "barcode": candidate["barcode"],
        "barcode_type": candidate["barcode_type"],
        "candidate_name_if_known": candidate["name_if_known"],
        "candidate_brand_if_known": candidate["brand_if_known"],
        "off_product_name": product_name,
        "off_brands": brands,
        "off_categories_tags": categories_tags,
        "off_main_category": main_category,
        "off_quantity": quantity,
        "off_last_modified_t": last_modified,
        "name_status": name_status,
        "brand_status": brand_status,
        "category_status": category_status,
        "quantity_status": quantity_status,
        "source_match_status": "matched",
        "off_source_row_count": str(aggregate.source_row_count),
        "candidate_source_reference": candidate["source_reference"],
        "candidate_source_content_sha256": candidate["source_content_sha256"],
        "off_source_content_sha256": catalog_tool.record_hash(
            {
                "barcode": aggregate.barcode,
                "supporting_source_hashes": sorted(aggregate.source_hashes),
            }
        ),
        "retrieved_at": candidate["retrieved_at"],
        "rights_class": candidate["rights_class"],
        "rights_reference": candidate["rights_reference"],
        "resolution_record_sha256": "",
    }
    row["resolution_record_sha256"] = catalog_tool.record_hash(
        {header: row[header] for header in RESOLUTION_HEADERS if header != "resolution_record_sha256"}
    )
    return row


def _build_metrics(
    candidate_rows: list[dict[str, str]],
    resolution_rows: list[dict[str, str]],
    scan_metrics: dict[str, Any],
) -> dict[str, Any]:
    total = len(resolution_rows)
    metrics = {
        "candidates_total": len(candidate_rows),
        "candidates_valid": len(candidate_rows),
        **scan_metrics,
        "matched_candidates": total,
        "missing_candidates": len(candidate_rows) - total,
        "with_name": sum(bool(row["off_product_name"]) for row in resolution_rows),
        "without_name": sum(not row["off_product_name"] for row in resolution_rows),
        "with_brand": sum(bool(row["off_brands"]) for row in resolution_rows),
        "without_brand": sum(not row["off_brands"] for row in resolution_rows),
        "with_categories_tags": sum(
            bool(row["off_categories_tags"]) for row in resolution_rows
        ),
        "without_categories_tags": sum(
            not row["off_categories_tags"] for row in resolution_rows
        ),
        "with_main_category": sum(bool(row["off_main_category"]) for row in resolution_rows),
        "without_main_category": sum(
            not row["off_main_category"] for row in resolution_rows
        ),
        "with_category": sum(row["category_status"] == "available" for row in resolution_rows),
        "without_category": sum(row["category_status"] == "missing" for row in resolution_rows),
        "with_quantity": sum(bool(row["off_quantity"]) for row in resolution_rows),
        "without_quantity": sum(not row["off_quantity"] for row in resolution_rows),
        "with_all_category_main_quantity": sum(
            bool(row["off_categories_tags"])
            and bool(row["off_main_category"])
            and bool(row["off_quantity"])
            for row in resolution_rows
        ),
        "name_conflicts": sum(row["name_status"] == "conflict" for row in resolution_rows),
        "brand_conflicts": sum(row["brand_status"] == "conflict" for row in resolution_rows),
        "category_conflicts": sum(
            row["category_status"] == "conflict" for row in resolution_rows
        ),
        "quantity_conflicts": sum(
            row["quantity_status"] == "conflict" for row in resolution_rows
        ),
        "ean13_count": sum(row["barcode_type"] == "ean13" for row in resolution_rows),
        "ean8_count": sum(row["barcode_type"] == "ean8" for row in resolution_rows),
        "upc_count": sum(row["barcode_type"] == "upc" for row in resolution_rows),
        "gtin14_count": sum(row["barcode_type"] == "gtin" for row in resolution_rows),
        "network_access": False,
        "database_access": False,
        "uuid_generation": False,
    }
    return metrics


def _write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=RESOLUTION_HEADERS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def _validate_resolution_output(path: Path, expected_barcodes: set[str]) -> None:
    try:
        handle = path.open("r", encoding="utf-8-sig", newline="")
    except OSError as error:
        raise ResolutionToolError(f"Cannot read temporary resolution output {path}: {error}") from error
    with handle:
        try:
            reader = csv.DictReader(handle, strict=True)
            if reader.fieldnames != RESOLUTION_HEADERS:
                raise ResolutionValidationError("Resolution output header is invalid")
            rows = list(reader)
        except (csv.Error, UnicodeError) as error:
            raise ResolutionValidationError(f"Cannot parse resolution output: {error}") from error

    if len(rows) != len(expected_barcodes):
        raise ResolutionValidationError("Resolution output row count differs from candidates input")
    actual_barcodes = [row["barcode"] for row in rows]
    if len(actual_barcodes) != len(set(actual_barcodes)):
        raise ResolutionValidationError("Resolution output contains duplicate barcodes")
    if set(actual_barcodes) != expected_barcodes:
        raise ResolutionValidationError("Resolution output barcode set differs from candidates input")
    if actual_barcodes != sorted(actual_barcodes):
        raise ResolutionValidationError("Resolution output is not ordered by barcode")

    for row_number, row in enumerate(rows, start=2):
        if row["source_match_status"] != "matched":
            raise ResolutionValidationError(f"Resolution row {row_number} is not matched")
        try:
            source_count = int(row["off_source_row_count"])
        except ValueError as error:
            raise ResolutionValidationError(
                f"Resolution row {row_number} has invalid off_source_row_count"
            ) from error
        if source_count < 1:
            raise ResolutionValidationError(
                f"Resolution row {row_number} has no supporting OFF source rows"
            )
        for status_field in (
            "name_status",
            "brand_status",
            "category_status",
            "quantity_status",
        ):
            if row[status_field] not in STATUS_VALUES:
                raise ResolutionValidationError(
                    f"Resolution row {row_number} has invalid {status_field}"
                )
        if not CANDIDATE_SHA256_RE.fullmatch(row["candidate_source_content_sha256"]):
            raise ResolutionValidationError(
                f"Resolution row {row_number} has invalid candidate_source_content_sha256"
            )
        for hash_field in ("off_source_content_sha256", "resolution_record_sha256"):
            if not SHA256_RE.fullmatch(row[hash_field]):
                raise ResolutionValidationError(
                    f"Resolution row {row_number} has invalid {hash_field}"
                )
        expected_hash = catalog_tool.record_hash(
            {
                header: row[header]
                for header in RESOLUTION_HEADERS
                if header != "resolution_record_sha256"
            }
        )
        if row["resolution_record_sha256"] != expected_hash:
            raise ResolutionValidationError(
                f"Resolution row {row_number} has inconsistent resolution_record_sha256"
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
    temporary_path = Path(handle.name)
    handle.close()
    return temporary_path


def build_snapshot(
    *,
    candidates_path: Path,
    off_input_path: Path,
    output_path: Path,
    metrics_path: Path,
) -> dict[str, Any]:
    paths = [
        Path(path).expanduser().resolve()
        for path in (candidates_path, off_input_path, output_path, metrics_path)
    ]
    candidates_path, off_input_path, output_path, metrics_path = paths
    if output_path == metrics_path:
        raise ResolutionToolError("--output and --metrics must be distinct")
    if output_path in (candidates_path, off_input_path) or metrics_path in (
        candidates_path,
        off_input_path,
    ):
        raise ResolutionToolError("Output paths must not overwrite inputs")

    candidate_rows, candidate_report = _load_candidates(candidates_path)
    candidate_barcodes = {row["barcode"] for row in candidate_rows}
    headers = _read_off_header(off_input_path)
    scan_metrics = {
        "off_rows_scanned": 0,
        "off_candidate_rows_matched": 0,
        "duplicate_off_rows": 0,
        "off_malformed_csv_rows": 0,
    }
    aggregates = _scan_off(
        off_input_path,
        headers=headers,
        candidate_barcodes=candidate_barcodes,
        metrics=scan_metrics,
    )
    missing = sorted(candidate_barcodes.difference(aggregates))
    if missing:
        preview = ", ".join(missing[:20])
        suffix = "" if len(missing) <= 20 else f" (+{len(missing) - 20} more)"
        raise ResolutionValidationError(
            f"OFF snapshot is missing {len(missing)} candidate barcode(s): {preview}{suffix}"
        )

    resolution_rows = [
        _resolution_row(candidate, aggregates[candidate["barcode"]])
        for candidate in candidate_rows
    ]
    metrics = _build_metrics(candidate_rows, resolution_rows, scan_metrics)
    metrics["candidates_valid"] = candidate_report["valid_rows"]

    final_and_temp: list[tuple[Path, Path]] = []
    try:
        output_temp = _temporary_output(output_path)
        final_and_temp.append((output_path, output_temp))
        metrics_temp = _temporary_output(metrics_path)
        final_and_temp.append((metrics_path, metrics_temp))
        _write_csv(output_temp, resolution_rows)
        _validate_resolution_output(output_temp, candidate_barcodes)
        metrics_temp.write_text(
            json.dumps(metrics, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
            encoding="utf-8",
        )
        os.replace(metrics_temp, metrics_path)
        os.replace(output_temp, output_path)
    finally:
        for _, temporary_path in final_and_temp:
            try:
                temporary_path.unlink(missing_ok=True)
            except OSError:
                pass
    return metrics


def human_report(metrics: dict[str, Any]) -> str:
    lines = [
        "Candidate Resolution Snapshot: SUCCESS",
        f"Candidates: {metrics['candidates_total']}",
        f"Matched in OFF snapshot: {metrics['matched_candidates']}",
        f"Missing: {metrics['missing_candidates']}",
    ]
    if metrics["off_malformed_csv_rows"]:
        lines.append(
            f"Malformed OFF CSV rows skipped: {metrics['off_malformed_csv_rows']}"
        )
    lines.extend(
        [
            f"With name: {metrics['with_name']}",
            f"With brand: {metrics['with_brand']}",
            f"With category: {metrics['with_category']}",
            f"With quantity: {metrics['with_quantity']}",
            "Network access: none",
            "Database access: none",
            "UUID generation: none",
        ]
    )
    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    build = subparsers.add_parser("build", help="Build an A2.0 factual resolution snapshot")
    build.add_argument("--candidates", required=True, type=_path)
    build.add_argument("--off-input", required=True, type=_path)
    build.add_argument("--output", required=True, type=_path)
    build.add_argument("--metrics", required=True, type=_path)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        metrics = build_snapshot(
            candidates_path=args.candidates,
            off_input_path=args.off_input,
            output_path=args.output,
            metrics_path=args.metrics,
        )
        print(human_report(metrics))
        return 0
    except ResolutionValidationError as error:
        print(f"VALIDATION ERROR: {error}", file=sys.stderr)
        return 1
    except (ResolutionToolError, OSError) as error:
        print(f"TOOL ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
