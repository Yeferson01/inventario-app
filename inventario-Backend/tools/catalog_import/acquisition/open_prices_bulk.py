#!/usr/bin/env python3
"""Extract Colombia catalog candidates from local Open Prices JSONL gzip dumps."""

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
from typing import Any, Iterator, Sequence


CATALOG_IMPORT_DIR = Path(__file__).resolve().parents[1]
if str(CATALOG_IMPORT_DIR) not in sys.path:
    sys.path.insert(0, str(CATALOG_IMPORT_DIR))

import catalog_tool  # noqa: E402
from acquisition import candidate_tool  # noqa: E402


RIGHTS_CLASS = "open_dataset_odbl_share_alike"
BARCODE_TYPES = {8: "ean8", 12: "upc", 13: "ean13", 14: "gtin"}
OFF_GENERATED_NO_BARCODE_RE = re.compile(r"^200\d{10}$")

EVIDENCE_HEADERS = [
    "barcode",
    "price_id",
    "location_id",
    "price_date",
    "product_name_if_known",
    "source_reference",
    "raw_price_sha256",
    "raw_location_sha256",
    "retrieved_at",
    "rights_class",
    "rights_reference",
    "name_conflict",
]

REJECT_HEADERS = [
    "source_dataset",
    "source_row",
    "product_code_if_any",
    "reason_code",
    "reason",
]


class OpenPricesBulkError(Exception):
    """Usage, I/O, or incompatible source-data error (exit code 2)."""


class CandidateValidationError(Exception):
    """Generated candidate data violates the A1.1 contract (exit code 1)."""


@dataclass
class BarcodeAggregate:
    barcode: str
    barcode_type: str
    raw_barcodes: set[str] = field(default_factory=set)
    location_ids: set[str] = field(default_factory=set)
    supporting_hashes: set[str] = field(default_factory=set)
    evidence: list[dict[str, str]] = field(default_factory=list)
    names: dict[str, set[str]] = field(default_factory=dict)
    observation_count: int = 0


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
        "locations_rows_total": 0,
        "locations_valid_rows": 0,
        "locations_colombia": 0,
        "locations_malformed_json": 0,
        "locations_missing_id": 0,
        "locations_missing_country_code": 0,
        "locations_non_colombia": 0,
        "prices_rows_total": 0,
        "prices_malformed_json": 0,
        "product_prices": 0,
        "non_product_prices": 0,
        "prices_missing_location_id": 0,
        "prices_in_colombia": 0,
        "prices_non_colombia_location": 0,
        "missing_product_code": 0,
        "unsupported_barcode": 0,
        "invalid_checksum": 0,
        "invalid_barcode": 0,
        "scientific_notation": 0,
        "generated_or_internal_identifier": 0,
        "restricted_products": 0,
        "valid_gtin_observations": 0,
        "unique_valid_gtins": 0,
        "accepted_candidates": 0,
        "candidate_name_conflicts": 0,
        "distinct_colombia_locations_used": 0,
        "duplicate_price_observations_skipped": 0,
        "max_candidates_applied": max_candidates is not None,
        "max_candidates_limit": max_candidates,
        "network_access": False,
        "database_access": False,
        "uuid_generation": False,
    }


def _reject(
    rejects: csv.DictWriter,
    *,
    dataset: str,
    row: int,
    code: str,
    reason: str,
    product_code: Any = "",
) -> None:
    product_code_text = product_code if isinstance(product_code, str) else ""
    rejects.writerow(
        {
            "source_dataset": dataset,
            "source_row": str(row),
            "product_code_if_any": product_code_text,
            "reason_code": code,
            "reason": reason,
        }
    )


def _iter_jsonl_gzip(
    path: Path,
    *,
    dataset: str,
    metrics: dict[str, Any],
    rejects: csv.DictWriter,
) -> Iterator[tuple[int, dict[str, Any], str]]:
    total_key = f"{dataset}_rows_total"
    malformed_key = f"{dataset}_malformed_json"
    try:
        handle = gzip.open(path, "rt", encoding="utf-8-sig", newline="")
    except OSError as error:
        raise OpenPricesBulkError(f"Cannot open {dataset} dump {path}: {error}") from error

    try:
        with handle:
            for row_number, line in enumerate(handle, start=1):
                metrics[total_key] += 1
                try:
                    value = json.loads(line)
                except (json.JSONDecodeError, UnicodeError) as error:
                    metrics[malformed_key] += 1
                    _reject(
                        rejects,
                        dataset=dataset,
                        row=row_number,
                        code="malformed_json",
                        reason=f"Invalid JSON object: {error.msg if isinstance(error, json.JSONDecodeError) else error}",
                    )
                    continue
                if not isinstance(value, dict):
                    metrics[malformed_key] += 1
                    _reject(
                        rejects,
                        dataset=dataset,
                        row=row_number,
                        code="malformed_json",
                        reason="JSON line must contain an object",
                    )
                    continue
                yield row_number, value, catalog_tool.record_hash(value)
    except (OSError, EOFError, gzip.BadGzipFile, UnicodeError) as error:
        raise OpenPricesBulkError(f"Cannot read {dataset} dump {path}: {error}") from error


def _identifier(value: Any) -> str | None:
    if isinstance(value, bool) or not isinstance(value, (str, int)):
        return None
    normalized = str(value).strip()
    return normalized or None


def _load_colombia_locations(
    path: Path,
    metrics: dict[str, Any],
    rejects: csv.DictWriter,
) -> dict[str, str]:
    colombia: dict[str, str] = {}
    seen_locations: dict[str, str] = {}
    saw_object = False
    saw_schema_marker = False

    for row_number, record, row_hash in _iter_jsonl_gzip(
        path, dataset="locations", metrics=metrics, rejects=rejects
    ):
        saw_object = True
        saw_schema_marker = saw_schema_marker or bool(
            {"id", "osm_address_country_code"}.intersection(record)
        )
        location_id = _identifier(record.get("id"))
        if location_id is None:
            metrics["locations_missing_id"] += 1
            _reject(
                rejects,
                dataset="locations",
                row=row_number,
                code="missing_location_id",
                reason="Location record has no usable id",
            )
            continue

        country_code = record.get("osm_address_country_code")
        if not isinstance(country_code, str) or not country_code.strip():
            metrics["locations_missing_country_code"] += 1
            _reject(
                rejects,
                dataset="locations",
                row=row_number,
                code="missing_country_code",
                reason="Location record has no usable osm_address_country_code",
            )
            continue

        metrics["locations_valid_rows"] += 1
        prior_hash = seen_locations.get(location_id)
        if prior_hash is not None and prior_hash != row_hash:
            raise OpenPricesBulkError(f"Conflicting location records for id {location_id!r}")
        seen_locations[location_id] = row_hash
        if country_code.strip().casefold() != "co":
            metrics["locations_non_colombia"] += 1
            continue

        colombia[location_id] = row_hash

    if saw_object and not saw_schema_marker:
        raise OpenPricesBulkError(
            "Locations dump is incompatible: no id or osm_address_country_code fields found"
        )
    metrics["locations_colombia"] = len(colombia)
    return colombia


def _is_explicitly_age_restricted(record: dict[str, Any]) -> bool:
    """Recognize only explicit boolean flags; never infer from names or free text."""
    return record.get("age_restricted") is True or record.get("is_age_restricted") is True


def _visible_name(value: Any) -> str:
    if not isinstance(value, str):
        return ""
    return catalog_tool.normalize_visible_text(value)


def _name_result(aggregate: BarcodeAggregate) -> tuple[str, bool]:
    if not aggregate.names:
        return "", False
    if len(aggregate.names) > 1:
        return "", True
    display_values = next(iter(aggregate.names.values()))
    return sorted(display_values, key=lambda value: (value.casefold(), value))[0], False


def _process_prices(
    path: Path,
    *,
    colombia_locations: dict[str, str],
    source_reference: str,
    rights_reference: str,
    retrieved_at: str,
    metrics: dict[str, Any],
    rejects: csv.DictWriter,
) -> dict[str, BarcodeAggregate]:
    aggregates: dict[str, BarcodeAggregate] = {}
    seen_observations: dict[tuple[str, str], str] = {}
    saw_object = False
    saw_schema_marker = False

    for row_number, record, raw_price_hash in _iter_jsonl_gzip(
        path, dataset="prices", metrics=metrics, rejects=rejects
    ):
        saw_object = True
        saw_schema_marker = saw_schema_marker or bool(
            {"id", "type", "product_code", "location_id", "date"}.intersection(record)
        )
        product_code_value = record.get("product_code")

        if record.get("type") != "PRODUCT":
            metrics["non_product_prices"] += 1
            _reject(
                rejects,
                dataset="prices",
                row=row_number,
                product_code=product_code_value,
                code="non_product_price",
                reason="Only records with type exactly PRODUCT can participate",
            )
            continue
        metrics["product_prices"] += 1

        location_id = _identifier(record.get("location_id"))
        if location_id is None:
            metrics["prices_missing_location_id"] += 1
            _reject(
                rejects,
                dataset="prices",
                row=row_number,
                product_code=product_code_value,
                code="missing_location_id",
                reason="PRODUCT price has no usable location_id",
            )
            continue
        if location_id not in colombia_locations:
            metrics["prices_non_colombia_location"] += 1
            continue
        metrics["prices_in_colombia"] += 1

        duplicate_of = record.get("duplicate_of")
        if duplicate_of is not None and not (
            isinstance(duplicate_of, str) and not duplicate_of.strip()
        ):
            metrics["duplicate_price_observations_skipped"] += 1
            _reject(
                rejects,
                dataset="prices",
                row=row_number,
                product_code=product_code_value,
                code="duplicate_source_observation",
                reason="Open Prices duplicate_of is populated",
            )
            continue

        if product_code_value is None or (
            isinstance(product_code_value, str) and not product_code_value.strip()
        ):
            metrics["missing_product_code"] += 1
            _reject(
                rejects,
                dataset="prices",
                row=row_number,
                code="empty_product_code",
                reason="PRODUCT price has no non-empty product_code",
            )
            continue
        if not isinstance(product_code_value, str):
            metrics["invalid_barcode"] += 1
            _reject(
                rejects,
                dataset="prices",
                row=row_number,
                code="invalid_barcode",
                reason="product_code must be a JSON string; numeric conversion is forbidden",
            )
            continue

        raw_barcode = product_code_value
        barcode = raw_barcode.strip()
        if catalog_tool.SCIENTIFIC_NOTATION_RE.fullmatch(barcode):
            metrics["scientific_notation"] += 1
            metrics["invalid_barcode"] += 1
            _reject(
                rejects,
                dataset="prices",
                row=row_number,
                product_code=raw_barcode,
                code="invalid_barcode",
                reason="product_code must not use scientific notation",
            )
            continue
        if OFF_GENERATED_NO_BARCODE_RE.fullmatch(barcode):
            metrics["generated_or_internal_identifier"] += 1
            _reject(
                rejects,
                dataset="prices",
                row=row_number,
                product_code=raw_barcode,
                code="generated_or_internal_identifier",
                reason="OFF documents 13-digit 200-prefixed codes as assigned to products without a barcode",
            )
            continue
        barcode_type = BARCODE_TYPES.get(len(barcode))
        if barcode_type is None:
            metrics["unsupported_barcode"] += 1
            _reject(
                rejects,
                dataset="prices",
                row=row_number,
                product_code=raw_barcode,
                code="unsupported_barcode_length",
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
                dataset="prices",
                row=row_number,
                product_code=raw_barcode,
                code="invalid_barcode",
                reason=barcode_error,
            )
            continue
        if _is_explicitly_age_restricted(record):
            metrics["restricted_products"] += 1
            _reject(
                rejects,
                dataset="prices",
                row=row_number,
                product_code=raw_barcode,
                code="restricted_product",
                reason="Explicit boolean age-restriction flag is true",
            )
            continue

        price_id = _identifier(record.get("id")) or ""
        observation_key = ("id", price_id) if price_id else ("hash", raw_price_hash)
        prior_observation_hash = seen_observations.get(observation_key)
        if prior_observation_hash is not None:
            if prior_observation_hash != raw_price_hash:
                raise OpenPricesBulkError(
                    f"Conflicting price records for observation {observation_key!r}"
                )
            metrics["duplicate_price_observations_skipped"] += 1
            _reject(
                rejects,
                dataset="prices",
                row=row_number,
                product_code=raw_barcode,
                code="duplicate_source_observation",
                reason="Repeated Open Prices observation id or identical source object",
            )
            continue
        seen_observations[observation_key] = raw_price_hash

        aggregate = aggregates.setdefault(
            barcode, BarcodeAggregate(barcode=barcode, barcode_type=barcode_type)
        )
        aggregate.raw_barcodes.add(raw_barcode)
        aggregate.location_ids.add(location_id)
        aggregate.supporting_hashes.add(
            catalog_tool.record_hash(
                {
                    "raw_price_sha256": raw_price_hash,
                    "raw_location_sha256": colombia_locations[location_id],
                }
            )
        )
        aggregate.observation_count += 1

        product_name = _visible_name(record.get("product_name"))
        if product_name:
            semantic_name = catalog_tool.normalize_semantic_text(product_name)
            aggregate.names.setdefault(semantic_name, set()).add(product_name)

        aggregate.evidence.append(
            {
                "barcode": barcode,
                "price_id": price_id,
                "location_id": location_id,
                "price_date": _visible_name(record.get("date")),
                "product_name_if_known": product_name,
                "source_reference": source_reference,
                "raw_price_sha256": raw_price_hash,
                "raw_location_sha256": colombia_locations[location_id],
                "retrieved_at": retrieved_at,
                "rights_class": RIGHTS_CLASS,
                "rights_reference": rights_reference,
                "name_conflict": "false",
            }
        )
        metrics["valid_gtin_observations"] += 1

    if saw_object and not saw_schema_marker:
        raise OpenPricesBulkError(
            "Prices dump is incompatible: no id, type, product_code, location_id, or date fields found"
        )
    return aggregates


def _select_aggregates(
    aggregates: dict[str, BarcodeAggregate], max_candidates: int | None
) -> list[BarcodeAggregate]:
    ranked = sorted(
        aggregates.values(),
        key=lambda aggregate: (
            -len(aggregate.location_ids),
            -aggregate.observation_count,
            aggregate.barcode,
        ),
    )
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
    name, name_conflict = _name_result(aggregate)
    aggregate_hash = catalog_tool.record_hash(
        {
            "barcode": aggregate.barcode,
            "supporting_evidence_hashes": sorted(aggregate.supporting_hashes),
        }
    )
    return {
        "raw_barcode": sorted(aggregate.raw_barcodes)[0],
        "barcode": aggregate.barcode,
        "barcode_type": aggregate.barcode_type,
        "name_if_known": name,
        "brand_if_known": "",
        "source": "open_dataset",
        "source_channel": "open_prices",
        "source_reference": source_reference,
        "source_record_id": "",
        "retrieved_at": retrieved_at,
        "rights_class": RIGHTS_CLASS,
        "rights_reference": rights_reference,
        "can_persist_candidate": "true",
        "candidate_confidence": "medium",
        "colombia_evidence_type": "other_documented",
        "colombia_evidence_count": str(len(aggregate.location_ids)),
        "source_content_sha256": aggregate_hash,
        "notes": "name_conflict" if name_conflict else "",
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
    locations_path: Path,
    prices_path: Path,
    candidates_path: Path,
    evidence_path: Path,
    rejects_path: Path,
    metrics_path: Path,
    source_reference: str,
    rights_reference: str,
    retrieved_at: str,
) -> None:
    if not source_reference.strip():
        raise OpenPricesBulkError("--source-reference must not be empty")
    if not rights_reference.strip():
        raise OpenPricesBulkError("--rights-reference must not be empty")
    if not candidate_tool._validate_timestamp(retrieved_at):  # noqa: SLF001
        raise OpenPricesBulkError("--retrieved-at must be timezone-aware ISO 8601")
    outputs = [candidates_path, evidence_path, rejects_path, metrics_path]
    if len(set(outputs)) != len(outputs):
        raise OpenPricesBulkError("Output paths must be distinct")
    if {locations_path, prices_path}.intersection(outputs):
        raise OpenPricesBulkError("Output paths must not overwrite an input dump")


def extract(
    *,
    locations_path: Path,
    prices_path: Path,
    candidates_path: Path,
    evidence_path: Path,
    rejects_path: Path,
    metrics_path: Path,
    source_reference: str,
    rights_reference: str,
    retrieved_at: str,
    max_candidates: int | None = None,
) -> dict[str, Any]:
    """Run the offline extraction and atomically publish validated outputs."""
    paths = [
        locations_path,
        prices_path,
        candidates_path,
        evidence_path,
        rejects_path,
        metrics_path,
    ]
    (
        locations_path,
        prices_path,
        candidates_path,
        evidence_path,
        rejects_path,
        metrics_path,
    ) = [Path(path).expanduser().resolve() for path in paths]
    _validate_arguments(
        locations_path=locations_path,
        prices_path=prices_path,
        candidates_path=candidates_path,
        evidence_path=evidence_path,
        rejects_path=rejects_path,
        metrics_path=metrics_path,
        source_reference=source_reference,
        rights_reference=rights_reference,
        retrieved_at=retrieved_at,
    )
    if max_candidates is not None and max_candidates < 1:
        raise OpenPricesBulkError("max_candidates must be a positive integer")

    metrics = _new_metrics(max_candidates)
    final_and_temp: list[tuple[Path, Path]] = []
    try:
        rejects_temp = _temporary_output(rejects_path)
        final_and_temp.append((rejects_path, rejects_temp))
        with rejects_temp.open("w", encoding="utf-8", newline="") as rejects_handle:
            reject_writer = csv.DictWriter(
                rejects_handle, fieldnames=REJECT_HEADERS, lineterminator="\n"
            )
            reject_writer.writeheader()
            colombia_locations = _load_colombia_locations(
                locations_path, metrics, reject_writer
            )
            aggregates = _process_prices(
                prices_path,
                colombia_locations=colombia_locations,
                source_reference=source_reference,
                rights_reference=rights_reference,
                retrieved_at=retrieved_at,
                metrics=metrics,
                rejects=reject_writer,
            )
        metrics["unique_valid_gtins"] = len(aggregates)

        selected = _select_aggregates(aggregates, max_candidates)
        selected_barcodes = {aggregate.barcode for aggregate in selected}
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
            _, name_conflict = _name_result(aggregate)
            for evidence in aggregate.evidence:
                evidence["name_conflict"] = "true" if name_conflict else "false"
                evidence_rows.append(evidence)
        evidence_rows.sort(
            key=lambda row: (
                row["barcode"],
                row["location_id"],
                row["price_id"],
                row["price_date"],
                row["raw_price_sha256"],
            )
        )

        metrics["accepted_candidates"] = len(candidate_rows)
        metrics["candidate_name_conflicts"] = sum(
            1 for aggregate in selected if _name_result(aggregate)[1]
        )
        metrics["distinct_colombia_locations_used"] = len(
            {
                location_id
                for aggregate in selected
                for location_id in aggregate.location_ids
                if aggregate.barcode in selected_barcodes
            }
        )

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

        # Each file is atomic. Candidates are published last, after their contract validation.
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
            "Open Prices Colombia extraction: SUCCESS",
            f"Locations scanned: {metrics['locations_rows_total']}",
            f"Colombia locations: {metrics['locations_colombia']}",
            f"Prices scanned: {metrics['prices_rows_total']}",
            f"Colombia PRODUCT observations: {metrics['prices_in_colombia']}",
            f"Valid GTIN observations: {metrics['valid_gtin_observations']}",
            f"Unique valid GTINs: {metrics['unique_valid_gtins']}",
            f"Accepted candidates: {metrics['accepted_candidates']}",
            f"Name conflicts: {metrics['candidate_name_conflicts']}",
            "Network access: none",
            "Database access: none",
            "UUID generation: none",
        ]
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    extract_parser = subparsers.add_parser("extract", help="Extract local Open Prices dumps")
    extract_parser.add_argument("--locations", required=True, type=_path)
    extract_parser.add_argument("--prices", required=True, type=_path)
    extract_parser.add_argument("--candidates", required=True, type=_path)
    extract_parser.add_argument("--evidence", required=True, type=_path)
    extract_parser.add_argument("--rejects", required=True, type=_path)
    extract_parser.add_argument("--metrics", required=True, type=_path)
    extract_parser.add_argument("--source-reference", required=True)
    extract_parser.add_argument("--rights-reference", required=True)
    extract_parser.add_argument("--retrieved-at", required=True)
    extract_parser.add_argument("--max-candidates", type=_positive_int)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        metrics = extract(
            locations_path=args.locations,
            prices_path=args.prices,
            candidates_path=args.candidates,
            evidence_path=args.evidence,
            rejects_path=args.rejects,
            metrics_path=args.metrics,
            source_reference=args.source_reference,
            rights_reference=args.rights_reference,
            retrieved_at=args.retrieved_at,
            max_candidates=args.max_candidates,
        )
        print(human_report(metrics))
        return 0
    except CandidateValidationError as error:
        print(f"VALIDATION ERROR: {error}", file=sys.stderr)
        return 1
    except (OpenPricesBulkError, OSError) as error:
        print(f"TOOL ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
