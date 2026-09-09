#!/usr/bin/env python3
"""Extract Colombia catalog candidates from a local Open Food Facts CSV gzip dump."""

from __future__ import annotations

import argparse
import csv
import gzip
import json
import os
import re
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Sequence


CATALOG_IMPORT_DIR = Path(__file__).resolve().parents[1]
if str(CATALOG_IMPORT_DIR) not in sys.path:
    sys.path.insert(0, str(CATALOG_IMPORT_DIR))

import catalog_tool  # noqa: E402
from acquisition import candidate_tool  # noqa: E402


RIGHTS_CLASS = "open_dataset_odbl_share_alike"
BARCODE_TYPES = {8: "ean8", 12: "upc", 13: "ean13", 14: "gtin"}

# Open Food Facts documents 13-digit codes beginning with its reserved 200 prefix
# as assigned identifiers for products without a barcode. Do not broaden this rule.
OFF_GENERATED_NO_BARCODE_RE = re.compile(r"^200\d{10}$")
EXCLUDED_CATEGORY_TAGS = {"en:alcoholic-beverages"}

EVIDENCE_HEADERS = [
    "barcode",
    "source_row",
    "product_name_if_known",
    "brand_if_known",
    "countries_column",
    "countries_tags",
    "source_reference",
    "raw_row_sha256",
    "retrieved_at",
    "rights_class",
    "rights_reference",
    "name_conflict",
    "brand_conflict",
]

REJECT_HEADERS = ["source_row", "code_if_any", "reason_code", "reason"]
SUPPORTED_DELIMITERS = ("\t", ",", ";")


class OpenFoodFactsBulkError(Exception):
    """Usage, I/O, or incompatible source-data error (exit code 2)."""


class CandidateValidationError(Exception):
    """Generated candidate data violates the A1.1 contract (exit code 1)."""


@dataclass(frozen=True)
class HeaderContract:
    headers: list[str]
    delimiter: str
    countries_column: str


@dataclass
class BarcodeAggregate:
    barcode: str
    barcode_type: str
    raw_codes: set[str] = field(default_factory=set)
    source_hashes: set[str] = field(default_factory=set)
    evidence: list[dict[str, str]] = field(default_factory=list)
    names: dict[str, set[str]] = field(default_factory=dict)
    brands: dict[str, set[str]] = field(default_factory=dict)
    evidence_count: int = 0


def _path(value: str) -> Path:
    return Path(value).expanduser().resolve()


def _positive_int(value: str) -> int:
    try:
        parsed = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be a positive integer") from error
    if parsed < 1:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return parsed


def _new_metrics(max_candidates: int | None) -> dict[str, Any]:
    return {
        "rows_total": 0,
        "rows_colombia": 0,
        "rows_not_colombia": 0,
        "malformed_csv_rows": 0,
        "invalid_country_fields": 0,
        "missing_code": 0,
        "generated_or_internal_identifier": 0,
        "unsupported_barcode": 0,
        "invalid_checksum": 0,
        "invalid_barcode": 0,
        "scientific_notation": 0,
        "valid_gtin_rows": 0,
        "duplicate_source_rows": 0,
        "duplicate_gtin_rows": 0,
        "unique_valid_gtins": 0,
        "accepted_candidates": 0,
        "candidate_name_conflicts": 0,
        "candidate_brand_conflicts": 0,
        "excluded_products": 0,
        "evidence_rows": 0,
        "countries_column_used": "",
        "input_delimiter": "",
        "max_candidates_applied": max_candidates is not None,
        "max_candidates_limit": max_candidates,
        "network_access": False,
        "database_access": False,
        "uuid_generation": False,
    }


def _reject(
    writer: csv.DictWriter,
    *,
    row_number: int,
    reason_code: str,
    reason: str,
    code: Any = "",
) -> None:
    writer.writerow(
        {
            "source_row": str(row_number),
            "code_if_any": code if isinstance(code, str) else "",
            "reason_code": reason_code,
            "reason": reason,
        }
    )


def _parse_header_line(header_line: str, delimiter: str) -> list[str] | None:
    try:
        return next(csv.reader([header_line], delimiter=delimiter, strict=True))
    except (csv.Error, StopIteration):
        return None


def _detect_header(
    input_path: Path, countries_column_override: str | None
) -> HeaderContract:
    try:
        with gzip.open(input_path, "rt", encoding="utf-8-sig", newline="") as handle:
            header_line = handle.readline()
    except (OSError, EOFError, gzip.BadGzipFile, UnicodeError) as error:
        raise OpenFoodFactsBulkError(f"Cannot read input dump {input_path}: {error}") from error

    if not header_line:
        raise OpenFoodFactsBulkError("Input dump is empty and has no CSV header")

    parsed_options = [
        (delimiter, parsed)
        for delimiter in SUPPORTED_DELIMITERS
        if (parsed := _parse_header_line(header_line, delimiter)) is not None
    ]
    if not parsed_options:
        raise OpenFoodFactsBulkError("Cannot parse CSV header")
    max_columns = max(len(parsed) for _, parsed in parsed_options)
    best = [(delimiter, parsed) for delimiter, parsed in parsed_options if len(parsed) == max_columns]
    if max_columns > 1 and len(best) != 1:
        raise OpenFoodFactsBulkError("CSV header delimiter is ambiguous")
    delimiter, headers = best[0]

    if any(not header for header in headers):
        raise OpenFoodFactsBulkError("CSV header contains an empty column name")
    if len(headers) != len(set(headers)):
        raise OpenFoodFactsBulkError("CSV header contains duplicate column names")
    if "code" not in headers:
        raise OpenFoodFactsBulkError("CSV header is missing required column: code")

    if "countries_tags" in headers:
        countries_column = "countries_tags"
    elif countries_column_override:
        countries_column = countries_column_override
        if countries_column not in headers:
            raise OpenFoodFactsBulkError(
                f"CSV header is missing configured countries column: {countries_column}"
            )
    else:
        raise OpenFoodFactsBulkError(
            "CSV header is missing countries_tags and --countries-column was not provided"
        )
    if countries_column == "code":
        raise OpenFoodFactsBulkError("Countries column must be distinct from code")
    return HeaderContract(headers, delimiter, countries_column)


def _delimiter_name(delimiter: str) -> str:
    return {"\t": "tab", ",": "comma", ";": "semicolon"}[delimiter]


def _parse_tag_field(value: str) -> set[str] | None:
    """Parse comma-delimited OFF tags without substring or free-text matching."""
    visible = value.strip()
    if not visible:
        return set()
    tokens = [token.strip() for token in visible.split(",")]
    if any(not token for token in tokens):
        return None
    parsed: set[str] = set()
    for token in tokens:
        prefix, separator, slug = token.partition(":")
        if (
            separator != ":"
            or not re.fullmatch(r"[A-Za-z]{2,3}", prefix)
            or not slug
            or any(character.isspace() for character in slug)
            or ";" in slug
            or "|" in slug
        ):
            return None
        parsed.add(f"{prefix}:{slug}".casefold())
    return parsed


def _visible_hint(value: str) -> str:
    return catalog_tool.normalize_visible_text(value)


def _add_hint(values: dict[str, set[str]], value: str) -> None:
    visible = _visible_hint(value)
    if visible:
        values.setdefault(catalog_tool.normalize_semantic_text(visible), set()).add(visible)


def _resolved_hint(values: dict[str, set[str]]) -> tuple[str, bool]:
    if not values:
        return "", False
    if len(values) > 1:
        return "", True
    displays = next(iter(values.values()))
    return sorted(displays, key=lambda value: (value.casefold(), value))[0], False


def _row_code(row: list[str], contract: HeaderContract) -> str:
    try:
        return row[contract.headers.index("code")]
    except IndexError:
        return ""


def _process_rows(
    input_path: Path,
    *,
    contract: HeaderContract,
    source_reference: str,
    rights_reference: str,
    retrieved_at: str,
    rejects: csv.DictWriter,
    metrics: dict[str, Any],
) -> dict[str, BarcodeAggregate]:
    aggregates: dict[str, BarcodeAggregate] = {}
    seen_source_hashes: set[str] = set()

    try:
        handle = gzip.open(input_path, "rt", encoding="utf-8-sig", newline="")
    except OSError as error:
        raise OpenFoodFactsBulkError(f"Cannot open input dump {input_path}: {error}") from error

    try:
        with handle:
            reader = csv.reader(handle, delimiter=contract.delimiter, strict=True)
            try:
                actual_headers = next(reader)
            except (StopIteration, csv.Error) as error:
                raise OpenFoodFactsBulkError(f"Cannot parse CSV header: {error}") from error
            if actual_headers != contract.headers:
                raise OpenFoodFactsBulkError("CSV header changed between inspection and streaming")

            while True:
                try:
                    raw_row = next(reader)
                except StopIteration:
                    break
                except csv.Error as error:
                    metrics["rows_total"] += 1
                    metrics["malformed_csv_rows"] += 1
                    _reject(
                        rejects,
                        row_number=max(reader.line_num, 2),
                        reason_code="malformed_csv_row",
                        reason=f"CSV parser error: {error}",
                    )
                    continue

                row_number = reader.line_num
                metrics["rows_total"] += 1
                if len(raw_row) != len(contract.headers):
                    metrics["malformed_csv_rows"] += 1
                    _reject(
                        rejects,
                        row_number=row_number,
                        code=_row_code(raw_row, contract),
                        reason_code="malformed_csv_row",
                        reason=(
                            f"CSV row has {len(raw_row)} fields; expected {len(contract.headers)}"
                        ),
                    )
                    continue

                record = dict(zip(contract.headers, raw_row, strict=True))
                raw_country_field = record[contract.countries_column]
                country_tags = _parse_tag_field(raw_country_field)
                if country_tags is None:
                    metrics["invalid_country_fields"] += 1
                    _reject(
                        rejects,
                        row_number=row_number,
                        code=record["code"],
                        reason_code="invalid_country_field",
                        reason=(
                            f"{contract.countries_column} must contain comma-delimited OFF tags"
                        ),
                    )
                    continue
                if "en:colombia" not in country_tags:
                    metrics["rows_not_colombia"] += 1
                    continue
                metrics["rows_colombia"] += 1

                raw_code = record["code"]
                barcode = raw_code.strip()
                if not barcode:
                    metrics["missing_code"] += 1
                    _reject(
                        rejects,
                        row_number=row_number,
                        reason_code="empty_code",
                        reason="Colombia-tagged row has an empty code",
                    )
                    continue
                if catalog_tool.SCIENTIFIC_NOTATION_RE.fullmatch(barcode):
                    metrics["scientific_notation"] += 1
                    metrics["invalid_barcode"] += 1
                    _reject(
                        rejects,
                        row_number=row_number,
                        code=raw_code,
                        reason_code="invalid_barcode",
                        reason="code must not use scientific notation",
                    )
                    continue
                if OFF_GENERATED_NO_BARCODE_RE.fullmatch(barcode):
                    metrics["generated_or_internal_identifier"] += 1
                    _reject(
                        rejects,
                        row_number=row_number,
                        code=raw_code,
                        reason_code="generated_or_internal_identifier",
                        reason=(
                            "OFF documents 13-digit 200-prefixed codes as assigned to "
                            "products without a barcode"
                        ),
                    )
                    continue
                barcode_type = BARCODE_TYPES.get(len(barcode))
                if barcode_type is None:
                    metrics["unsupported_barcode"] += 1
                    _reject(
                        rejects,
                        row_number=row_number,
                        code=raw_code,
                        reason_code="unsupported_barcode_length",
                        reason="Only GTIN lengths 8, 12, 13, and 14 are supported",
                    )
                    continue
                barcode_error = catalog_tool.validate_barcode_shape(barcode, barcode_type)
                if barcode_error:
                    if "checksum" in barcode_error:
                        metrics["invalid_checksum"] += 1
                    else:
                        metrics["invalid_barcode"] += 1
                    _reject(
                        rejects,
                        row_number=row_number,
                        code=raw_code,
                        reason_code="invalid_barcode",
                        reason=barcode_error,
                    )
                    continue

                category_tags = _parse_tag_field(record.get("categories_tags", ""))
                if category_tags and category_tags.intersection(EXCLUDED_CATEGORY_TAGS):
                    metrics["excluded_products"] += 1
                    _reject(
                        rejects,
                        row_number=row_number,
                        code=raw_code,
                        reason_code="excluded_product",
                        reason="Structured categories_tags identifies an alcoholic beverage",
                    )
                    continue

                raw_row_hash = catalog_tool.record_hash(record)
                metrics["valid_gtin_rows"] += 1
                if raw_row_hash in seen_source_hashes:
                    metrics["duplicate_source_rows"] += 1
                    metrics["duplicate_gtin_rows"] += 1
                    _reject(
                        rejects,
                        row_number=row_number,
                        code=raw_code,
                        reason_code="duplicate_source_row",
                        reason="Identical source row was already processed",
                    )
                    continue
                seen_source_hashes.add(raw_row_hash)

                aggregate = aggregates.get(barcode)
                if aggregate is None:
                    aggregate = BarcodeAggregate(barcode=barcode, barcode_type=barcode_type)
                    aggregates[barcode] = aggregate
                else:
                    metrics["duplicate_gtin_rows"] += 1
                aggregate.raw_codes.add(raw_code)
                aggregate.source_hashes.add(raw_row_hash)
                aggregate.evidence_count += 1
                _add_hint(aggregate.names, record.get("product_name", ""))
                _add_hint(aggregate.brands, record.get("brands", ""))
                aggregate.evidence.append(
                    {
                        "barcode": barcode,
                        "source_row": str(row_number),
                        "product_name_if_known": _visible_hint(record.get("product_name", "")),
                        "brand_if_known": _visible_hint(record.get("brands", "")),
                        "countries_column": contract.countries_column,
                        "countries_tags": raw_country_field.strip(),
                        "source_reference": source_reference,
                        "raw_row_sha256": raw_row_hash,
                        "retrieved_at": retrieved_at,
                        "rights_class": RIGHTS_CLASS,
                        "rights_reference": rights_reference,
                        "name_conflict": "false",
                        "brand_conflict": "false",
                    }
                )
    except (OSError, EOFError, gzip.BadGzipFile, UnicodeError) as error:
        raise OpenFoodFactsBulkError(f"Cannot read input dump {input_path}: {error}") from error
    return aggregates


def _rank_key(aggregate: BarcodeAggregate) -> tuple[int, int, int, str]:
    name, _ = _resolved_hint(aggregate.names)
    brand, _ = _resolved_hint(aggregate.brands)
    return (-bool(name), -bool(brand), -aggregate.evidence_count, aggregate.barcode)


def _select_aggregates(
    aggregates: dict[str, BarcodeAggregate], max_candidates: int | None
) -> list[BarcodeAggregate]:
    ranked = sorted(aggregates.values(), key=_rank_key)
    if max_candidates is not None:
        return ranked[:max_candidates]
    return sorted(ranked, key=lambda aggregate: aggregate.barcode)


def _candidate_row(
    aggregate: BarcodeAggregate,
    *,
    source_reference: str,
    rights_reference: str,
    retrieved_at: str,
) -> dict[str, str]:
    name, name_conflict = _resolved_hint(aggregate.names)
    brand, brand_conflict = _resolved_hint(aggregate.brands)
    notes = []
    if name_conflict:
        notes.append("name_conflict")
    if brand_conflict:
        notes.append("brand_conflict")
    return {
        "raw_barcode": sorted(aggregate.raw_codes)[0],
        "barcode": aggregate.barcode,
        "barcode_type": aggregate.barcode_type,
        "name_if_known": name,
        "brand_if_known": brand,
        "source": "open_dataset",
        "source_channel": "open_food_facts",
        "source_reference": source_reference,
        "source_record_id": "",
        "retrieved_at": retrieved_at,
        "rights_class": RIGHTS_CLASS,
        "rights_reference": rights_reference,
        "can_persist_candidate": "true",
        "candidate_confidence": "medium",
        "colombia_evidence_type": "other_documented",
        "colombia_evidence_count": "1",
        "source_content_sha256": catalog_tool.record_hash(
            {
                "barcode": aggregate.barcode,
                "supporting_evidence_hashes": sorted(aggregate.source_hashes),
            }
        ),
        "notes": ";".join(notes),
    }


def _write_csv(path: Path, headers: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


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


def _validate_arguments(
    *,
    input_path: Path,
    candidates_path: Path,
    evidence_path: Path,
    rejects_path: Path,
    metrics_path: Path,
    source_reference: str,
    rights_reference: str,
    retrieved_at: str,
    countries_column: str | None,
) -> None:
    if not source_reference.strip():
        raise OpenFoodFactsBulkError("--source-reference must not be empty")
    if not rights_reference.strip():
        raise OpenFoodFactsBulkError("--rights-reference must not be empty")
    if not candidate_tool._validate_timestamp(retrieved_at):  # noqa: SLF001
        raise OpenFoodFactsBulkError("--retrieved-at must be timezone-aware ISO 8601")
    if countries_column is not None and countries_column != countries_column.strip():
        raise OpenFoodFactsBulkError("--countries-column must match the header exactly")
    outputs = [candidates_path, evidence_path, rejects_path, metrics_path]
    if len(set(outputs)) != len(outputs):
        raise OpenFoodFactsBulkError("Output paths must be distinct")
    if input_path in outputs:
        raise OpenFoodFactsBulkError("Output paths must not overwrite the input dump")


def extract(
    *,
    input_path: Path,
    candidates_path: Path,
    evidence_path: Path,
    rejects_path: Path,
    metrics_path: Path,
    source_reference: str,
    rights_reference: str,
    retrieved_at: str,
    countries_column: str | None = None,
    max_candidates: int | None = None,
) -> dict[str, Any]:
    """Run the offline extraction and atomically publish validated outputs."""
    resolved = [
        Path(path).expanduser().resolve()
        for path in (input_path, candidates_path, evidence_path, rejects_path, metrics_path)
    ]
    input_path, candidates_path, evidence_path, rejects_path, metrics_path = resolved
    _validate_arguments(
        input_path=input_path,
        candidates_path=candidates_path,
        evidence_path=evidence_path,
        rejects_path=rejects_path,
        metrics_path=metrics_path,
        source_reference=source_reference,
        rights_reference=rights_reference,
        retrieved_at=retrieved_at,
        countries_column=countries_column,
    )
    if max_candidates is not None and max_candidates < 1:
        raise OpenFoodFactsBulkError("max_candidates must be a positive integer")

    contract = _detect_header(input_path, countries_column)
    metrics = _new_metrics(max_candidates)
    metrics["countries_column_used"] = contract.countries_column
    metrics["input_delimiter"] = _delimiter_name(contract.delimiter)
    final_and_temp: list[tuple[Path, Path]] = []
    try:
        rejects_temp = _temporary_output(rejects_path)
        final_and_temp.append((rejects_path, rejects_temp))
        with rejects_temp.open("w", encoding="utf-8", newline="") as rejects_handle:
            reject_writer = csv.DictWriter(
                rejects_handle, fieldnames=REJECT_HEADERS, lineterminator="\n"
            )
            reject_writer.writeheader()
            aggregates = _process_rows(
                input_path,
                contract=contract,
                source_reference=source_reference,
                rights_reference=rights_reference,
                retrieved_at=retrieved_at,
                rejects=reject_writer,
                metrics=metrics,
            )
        metrics["unique_valid_gtins"] = len(aggregates)

        selected = _select_aggregates(aggregates, max_candidates)
        candidate_rows = [
            _candidate_row(
                aggregate,
                source_reference=source_reference,
                rights_reference=rights_reference,
                retrieved_at=retrieved_at,
            )
            for aggregate in selected
        ]
        evidence_rows: list[dict[str, str]] = []
        for aggregate in selected:
            _, name_conflict = _resolved_hint(aggregate.names)
            _, brand_conflict = _resolved_hint(aggregate.brands)
            for evidence in aggregate.evidence:
                evidence["name_conflict"] = "true" if name_conflict else "false"
                evidence["brand_conflict"] = "true" if brand_conflict else "false"
                evidence_rows.append(evidence)
        evidence_rows.sort(
            key=lambda row: (row["barcode"], row["raw_row_sha256"], row["source_row"])
        )

        metrics["accepted_candidates"] = len(candidate_rows)
        metrics["candidate_name_conflicts"] = sum(
            1 for aggregate in selected if _resolved_hint(aggregate.names)[1]
        )
        metrics["candidate_brand_conflicts"] = sum(
            1 for aggregate in selected if _resolved_hint(aggregate.brands)[1]
        )
        metrics["evidence_rows"] = len(evidence_rows)

        candidates_temp = _temporary_output(candidates_path)
        final_and_temp.append((candidates_path, candidates_temp))
        evidence_temp = _temporary_output(evidence_path)
        final_and_temp.append((evidence_path, evidence_temp))
        metrics_temp = _temporary_output(metrics_path)
        final_and_temp.append((metrics_path, metrics_temp))

        _write_csv(candidates_temp, candidate_tool.CANDIDATE_HEADERS, candidate_rows)
        candidate_report = candidate_tool.validate_candidates(input_path=candidates_temp)
        if not candidate_report["valid"]:
            raise CandidateValidationError(
                "Generated candidates failed A1.1 validation: "
                + json.dumps(candidate_report["blocking_errors"], ensure_ascii=False)
            )
        _write_csv(evidence_temp, EVIDENCE_HEADERS, evidence_rows)
        metrics_temp.write_text(
            json.dumps(metrics, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
            encoding="utf-8",
        )

        os.replace(evidence_temp, evidence_path)
        os.replace(rejects_temp, rejects_path)
        os.replace(metrics_temp, metrics_path)
        os.replace(candidates_temp, candidates_path)
    finally:
        for _, temporary_path in final_and_temp:
            try:
                temporary_path.unlink(missing_ok=True)
            except OSError:
                pass
    return metrics


def human_report(metrics: dict[str, Any]) -> str:
    return "\n".join(
        [
            "Open Food Facts Colombia extraction: SUCCESS",
            f"Rows scanned: {metrics['rows_total']}",
            f"Rows tagged Colombia: {metrics['rows_colombia']}",
            f"Valid GTIN rows: {metrics['valid_gtin_rows']}",
            f"Unique valid GTINs: {metrics['unique_valid_gtins']}",
            f"Accepted candidates: {metrics['accepted_candidates']}",
            f"Name conflicts: {metrics['candidate_name_conflicts']}",
            f"Brand conflicts: {metrics['candidate_brand_conflicts']}",
            "Network access: none",
            "Database access: none",
            "UUID generation: none",
        ]
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    extract_parser = subparsers.add_parser("extract", help="Extract a local OFF CSV gzip dump")
    extract_parser.add_argument("--input", required=True, type=_path)
    extract_parser.add_argument("--candidates", required=True, type=_path)
    extract_parser.add_argument("--evidence", required=True, type=_path)
    extract_parser.add_argument("--rejects", required=True, type=_path)
    extract_parser.add_argument("--metrics", required=True, type=_path)
    extract_parser.add_argument("--source-reference", required=True)
    extract_parser.add_argument("--rights-reference", required=True)
    extract_parser.add_argument("--retrieved-at", required=True)
    extract_parser.add_argument("--countries-column")
    extract_parser.add_argument("--max-candidates", type=_positive_int)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        metrics = extract(
            input_path=args.input,
            candidates_path=args.candidates,
            evidence_path=args.evidence,
            rejects_path=args.rejects,
            metrics_path=args.metrics,
            source_reference=args.source_reference,
            rights_reference=args.rights_reference,
            retrieved_at=args.retrieved_at,
            countries_column=args.countries_column,
            max_candidates=args.max_candidates,
        )
        print(human_report(metrics))
        return 0
    except CandidateValidationError as error:
        print(f"VALIDATION ERROR: {error}", file=sys.stderr)
        return 1
    except (
        OpenFoodFactsBulkError,
        candidate_tool.CandidateToolError,
        catalog_tool.CatalogToolError,
        OSError,
    ) as error:
        print(f"TOOL ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
