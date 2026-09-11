#!/usr/bin/env python3
"""P1.3 remote-aware master catalog planner and administrative RPC client."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile
import urllib.error
import urllib.request
import uuid
from copy import deepcopy
from decimal import Decimal, InvalidOperation
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any, Callable, Sequence

import catalog_tool


IMPORTER_VERSION = "1.0.0"
PLAN_VERSION = 1
SNAPSHOT_VERSION = 1
EXECUTION_MANIFEST_VERSION = 1
CHUNKING_CONTRACT = "master_ownership_greedy_v1"
MAX_MASTERS_PER_CHUNK = 100
MAX_BARCODES_PER_CHUNK = 500
DEFAULT_HTTP_TIMEOUT_SECONDS = 60


class ImporterError(Exception):
    """Safe, user-facing importer error."""


def stable_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_json(value: Any) -> str:
    return hashlib.sha256(stable_json(value).encode("utf-8")).hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ImporterError(f"Cannot read JSON file {path}: {error}") from error
    if not isinstance(value, dict):
        raise ImporterError(f"JSON file must contain an object: {path}")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")


def write_json_atomic(path: Path, value: dict[str, Any]) -> None:
    """Durably replace an administrative JSON artifact without partial writes."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="\n",
            prefix=f".{path.name}.",
            suffix=".tmp",
            dir=path.parent,
            delete=False,
        ) as handle:
            temporary_path = Path(handle.name)
            json.dump(value, handle, ensure_ascii=False, sort_keys=True, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
        temporary_path = None
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def parse_snapshot(value: dict[str, Any]) -> dict[str, Any]:
    if value.get("snapshot_version") != SNAPSHOT_VERSION:
        raise ImporterError(
            f"Unsupported snapshot_version {value.get('snapshot_version')!r}; expected {SNAPSHOT_VERSION}"
        )
    masters = value.get("masters")
    barcodes = value.get("global_barcodes")
    if not isinstance(masters, list) or not isinstance(barcodes, list):
        raise ImporterError("Snapshot masters and global_barcodes must be arrays")

    seen_master_ids: set[str] = set()
    for row in masters:
        if not isinstance(row, dict) or not catalog_tool.is_valid_uuid(str(row.get("id", "")).lower()):
            raise ImporterError("Snapshot contains an invalid master ID")
        master_id = str(row["id"]).lower()
        if master_id in seen_master_ids:
            raise ImporterError(f"Snapshot contains duplicate master ID: {master_id}")
        seen_master_ids.add(master_id)

    seen_barcode_ids: set[str] = set()
    for row in barcodes:
        if not isinstance(row, dict) or not catalog_tool.is_valid_uuid(str(row.get("id", "")).lower()):
            raise ImporterError("Snapshot contains an invalid barcode ID")
        barcode_id = str(row["id"]).lower()
        if barcode_id in seen_barcode_ids:
            raise ImporterError(f"Snapshot contains duplicate barcode ID: {barcode_id}")
        seen_barcode_ids.add(barcode_id)
        if row.get("scope") != "global":
            raise ImporterError("Snapshot global_barcodes contains a non-global row")

    return {
        "snapshot_version": SNAPSHOT_VERSION,
        "masters": sorted(masters, key=lambda row: str(row["id"])),
        "global_barcodes": sorted(barcodes, key=lambda row: str(row["id"])),
    }


def load_snapshot(path: Path) -> dict[str, Any]:
    return parse_snapshot(read_json(path))


def _decimal(value: Any) -> str:
    if value is None or value == "":
        return ""
    try:
        number = Decimal(str(value))
    except InvalidOperation as error:
        raise ImporterError(f"Snapshot contains invalid decimal: {value!r}") from error
    normalized = format(number.normalize(), "f")
    if "." in normalized:
        normalized = normalized.rstrip("0").rstrip(".")
    return normalized or "0"


def _catalog_import_metadata(row: dict[str, Any]) -> dict[str, Any]:
    metadata = row.get("metadata")
    if not isinstance(metadata, dict):
        return {}
    import_metadata = metadata.get("catalog_import")
    return import_metadata if isinstance(import_metadata, dict) else {}


def _record_for_plan(row: dict[str, Any], *, master: bool) -> dict[str, Any]:
    excluded = {"source_row", "barcode_normalized"}
    record = {key: value for key, value in row.items() if key not in excluded}
    if master:
        record["primary_barcode"] = row["barcode_normalized"]
    else:
        record["barcode"] = row["barcode_normalized"]
    return record


def _remote_master_matches(remote: dict[str, Any], desired: dict[str, Any]) -> bool:
    metadata = _catalog_import_metadata(remote)
    stored_hash = str(metadata.get("record_hash", "")).lower()
    if stored_hash and stored_hash == desired["record_hash"]:
        return True
    remote_values = {
        "primary_barcode": catalog_tool.normalize_barcode(remote.get("gtin") or remote.get("barcode")),
        "name": catalog_tool.normalize_visible_text(remote.get("name") or remote.get("product_name")),
        "brand": catalog_tool.normalize_visible_text(remote.get("brand")),
        "manufacturer": catalog_tool.normalize_visible_text(remote.get("manufacturer")),
        "category_name": catalog_tool.normalize_visible_text(remote.get("category_name") or remote.get("category")),
        "subcategory_name": catalog_tool.normalize_visible_text(remote.get("subcategory_name")),
        "package_size": _decimal(remote.get("package_size")),
        "package_unit": catalog_tool.normalize_visible_text(remote.get("package_unit")),
        "unit_type": catalog_tool.normalize_visible_text(remote.get("unit_type") or remote.get("unit")),
        "description": catalog_tool.normalize_visible_text(remote.get("description")),
        "source": catalog_tool.normalize_visible_text(remote.get("source")).lower(),
        "verification_status": catalog_tool.normalize_visible_text(remote.get("verification_status")).lower(),
        "confidence_score": _decimal(remote.get("confidence_score")),
        "source_reference": catalog_tool.normalize_visible_text(metadata.get("source_reference")),
        "image_source_key": catalog_tool.normalize_visible_text(metadata.get("image_source_key")),
        "image_license": catalog_tool.normalize_visible_text(metadata.get("image_license")).lower(),
        "image_attribution": catalog_tool.normalize_visible_text(metadata.get("image_attribution")),
    }
    desired_values = {key: desired.get(key, "") for key in remote_values}
    return remote_values == desired_values


def _remote_barcode_matches(remote: dict[str, Any], desired: dict[str, Any]) -> bool:
    metadata = _catalog_import_metadata(remote)
    stored_hash = str(metadata.get("record_hash", "")).lower()
    if stored_hash and stored_hash == desired["record_hash"]:
        return True
    return {
        "master_product_id": str(remote.get("master_product_id", "")).lower(),
        "barcode": catalog_tool.normalize_barcode(remote.get("barcode")),
        "barcode_type": str(remote.get("barcode_type", "")).lower(),
        "is_primary": bool(remote.get("is_primary")),
        "source": str(remote.get("source", "")).lower(),
        "confidence_score": _decimal(remote.get("confidence_score")),
        "source_reference": catalog_tool.normalize_visible_text(metadata.get("source_reference")),
    } == {
        "master_product_id": desired["master_product_id"],
        "barcode": desired["barcode"],
        "barcode_type": desired["barcode_type"],
        "is_primary": desired["is_primary"],
        "source": desired["source"],
        "confidence_score": desired["confidence_score"],
        "source_reference": desired["source_reference"],
    }


def _semantic_tuple(row: dict[str, Any], *, remote: bool = False) -> tuple[str, ...]:
    return (
        catalog_tool.normalize_semantic_text(row.get("name") or (row.get("product_name") if remote else "")),
        catalog_tool.normalize_semantic_text(row.get("brand")),
        _decimal(row.get("package_size")),
        catalog_tool.normalize_semantic_text(row.get("package_unit")),
        catalog_tool.normalize_semantic_text(row.get("unit_type") or (row.get("unit") if remote else "")),
    )


def _semantic_relation(desired: dict[str, Any], remote: dict[str, Any], threshold: Decimal) -> str | None:
    left = _semantic_tuple(desired)
    right = _semantic_tuple(remote, remote=True)
    if left == right:
        return "exact"
    if left[1:] != right[1:] or not left[0] or not right[0]:
        return None
    ratio = Decimal(str(SequenceMatcher(None, left[0], right[0]).ratio()))
    if left[0] in right[0] or right[0] in left[0] or ratio >= threshold:
        return "near"
    return None


def _entry(classification: str, reason: str, record: dict[str, Any], expected_version: int | None) -> dict[str, Any]:
    return {
        "classification": classification,
        "reason": reason,
        "expected_version": expected_version,
        "record": record,
    }


def _append(bucket: dict[str, list[dict[str, Any]]], entry: dict[str, Any]) -> None:
    key = {
        "INSERT": "inserts",
        "UPDATE": "updates",
        "NO_OP": "no_ops",
        "CONFLICT": "conflicts",
        "REVIEW": "reviews",
    }[entry["classification"]]
    bucket[key].append(entry)


def _empty_operations() -> dict[str, list[dict[str, Any]]]:
    return {"inserts": [], "updates": [], "no_ops": [], "conflicts": [], "reviews": []}


def build_import_plan(
    *,
    validation_report: dict[str, Any],
    snapshot: dict[str, Any],
    import_batch_id: str,
    near_duplicate_threshold: Decimal = Decimal("0.88"),
) -> dict[str, Any]:
    try:
        canonical_batch_id = str(uuid.UUID(import_batch_id))
    except (ValueError, AttributeError) as error:
        raise ImporterError("import_batch_id must be a canonical UUID") from error
    if canonical_batch_id != import_batch_id.lower():
        raise ImporterError("import_batch_id must be a canonical UUID")
    if not validation_report.get("valid"):
        raise ImporterError("P1.2 validation has blocking errors; no import plan can be produced")

    snapshot = parse_snapshot(snapshot)
    remote_masters = {str(row["id"]).lower(): row for row in snapshot["masters"]}
    remote_barcodes = {str(row["id"]).lower(): row for row in snapshot["global_barcodes"]}
    active_codes: dict[str, list[dict[str, Any]]] = {}
    tombstoned_codes: dict[str, list[dict[str, Any]]] = {}
    active_primary_by_master: dict[str, dict[str, Any]] = {}
    for row in snapshot["global_barcodes"]:
        code = catalog_tool.normalize_barcode(row.get("barcode"))
        if row.get("deleted_at") is not None:
            tombstoned_codes.setdefault(code, []).append(row)
        elif row.get("status") == "active":
            active_codes.setdefault(code, []).append(row)
            if row.get("is_primary"):
                active_primary_by_master[str(row.get("master_product_id", "")).lower()] = row

    desired_masters = [
        _record_for_plan(row, master=True)
        for row in validation_report["normalized_preview"]["masters"]
    ]
    desired_barcodes = [
        _record_for_plan(row, master=False)
        for row in validation_report["normalized_preview"]["barcodes"]
    ]
    desired_barcodes_by_id = {row["barcode_id"]: row for row in desired_barcodes}

    masters = _empty_operations()
    barcodes = _empty_operations()
    reviewed_master_ids: set[str] = set()

    local_near_ids: set[str] = set()
    for candidate in validation_report.get("semantic_duplicate_candidates", []):
        if candidate.get("classification") == "near":
            local_near_ids.update(candidate.get("master_product_ids", []))

    for desired in sorted(desired_masters, key=lambda row: row["master_product_id"]):
        master_id = desired["master_product_id"]
        remote = remote_masters.get(master_id)
        expected_version = int(remote["version"]) if remote is not None else None
        classification = "INSERT"
        reason = "master ID is absent and its primary barcode is available"

        if master_id in local_near_ids:
            classification, reason = "REVIEW", "near semantic duplicate exists inside the dataset"
        elif remote is not None and remote.get("deleted_at") is not None:
            classification, reason = "REVIEW", "master ID is tombstoned and cannot be restored implicitly"
        else:
            owners = active_codes.get(desired["primary_barcode"], [])
            if any(str(row.get("master_product_id", "")).lower() != master_id for row in owners):
                classification, reason = "CONFLICT", "primary barcode is active under another master"
            elif tombstoned_codes.get(desired["primary_barcode"]):
                classification, reason = "REVIEW", "primary barcode has a tombstoned historical row"
            elif remote is not None:
                current_primary = active_primary_by_master.get(master_id)
                if current_primary and catalog_tool.normalize_barcode(current_primary.get("barcode")) != desired["primary_barcode"]:
                    old_id = str(current_primary["id"]).lower()
                    explicit_old_alias = desired_barcodes_by_id.get(old_id)
                    if explicit_old_alias is None or explicit_old_alias.get("is_primary") is not False:
                        classification, reason = "REVIEW", "primary change does not explicitly preserve the previous primary as an alias"
                    else:
                        classification = "NO_OP" if _remote_master_matches(remote, desired) else "UPDATE"
                        reason = "existing master payload is unchanged" if classification == "NO_OP" else "existing master has allowed canonical changes"
                else:
                    classification = "NO_OP" if _remote_master_matches(remote, desired) else "UPDATE"
                    reason = "existing master payload is unchanged" if classification == "NO_OP" else "existing master has allowed canonical changes"
            else:
                for candidate in snapshot["masters"]:
                    if candidate.get("deleted_at") is not None or str(candidate["id"]).lower() == master_id:
                        continue
                    relation = _semantic_relation(desired, candidate, near_duplicate_threshold)
                    if relation:
                        classification, reason = "REVIEW", f"{relation} semantic candidate exists in the remote catalog"
                        break

        entry = _entry(classification, reason, desired, expected_version)
        _append(masters, entry)
        if classification == "REVIEW":
            reviewed_master_ids.add(master_id)

    for desired in sorted(desired_barcodes, key=lambda row: row["barcode_id"]):
        barcode_id = desired["barcode_id"]
        master_id = desired["master_product_id"]
        remote = remote_barcodes.get(barcode_id)
        expected_version = int(remote["version"]) if remote is not None else None
        classification = "INSERT"
        reason = "barcode ID and normalized code are absent"

        if master_id in reviewed_master_ids:
            classification, reason = "REVIEW", "owning master requires review"
        elif remote is not None and remote.get("deleted_at") is not None:
            classification, reason = "REVIEW", "barcode ID is tombstoned and cannot be restored implicitly"
        elif remote is not None and (
            str(remote.get("master_product_id", "")).lower() != master_id
            or catalog_tool.normalize_barcode(remote.get("barcode")) != desired["barcode"]
            or remote.get("scope") != "global"
        ):
            classification, reason = "CONFLICT", "barcode ID has contradictory remote identity"
        else:
            active_owners = active_codes.get(desired["barcode"], [])
            if any(str(row["id"]).lower() != barcode_id for row in active_owners):
                classification, reason = "CONFLICT", "normalized barcode is active under another barcode identity"
            elif any(str(row["id"]).lower() != barcode_id for row in tombstoned_codes.get(desired["barcode"], [])):
                classification, reason = "REVIEW", "normalized barcode has a tombstoned historical identity"
            elif remote is not None:
                classification = "NO_OP" if _remote_barcode_matches(remote, desired) else "UPDATE"
                reason = "existing barcode payload is unchanged" if classification == "NO_OP" else "existing barcode has allowed canonical changes"

        _append(barcodes, _entry(classification, reason, desired, expected_version))

    for bucket in (masters, barcodes):
        for entries in bucket.values():
            entries.sort(key=lambda entry: stable_json(entry))

    snapshot_hash = sha256_json(snapshot)
    blocking_count = len(masters["conflicts"]) + len(masters["reviews"]) + len(barcodes["conflicts"]) + len(barcodes["reviews"])
    plan: dict[str, Any] = {
        "plan_version": PLAN_VERSION,
        "importer_version": IMPORTER_VERSION,
        "dataset_version": validation_report["dataset_version"],
        "import_batch_id": canonical_batch_id,
        "snapshot_hash": snapshot_hash,
        "ready_to_apply": blocking_count == 0,
        "masters": masters,
        "barcodes": barcodes,
        "summary": {
            "master_inserts": len(masters["inserts"]),
            "master_updates": len(masters["updates"]),
            "master_no_ops": len(masters["no_ops"]),
            "master_conflicts": len(masters["conflicts"]),
            "master_reviews": len(masters["reviews"]),
            "barcode_inserts": len(barcodes["inserts"]),
            "barcode_updates": len(barcodes["updates"]),
            "barcode_no_ops": len(barcodes["no_ops"]),
            "barcode_conflicts": len(barcodes["conflicts"]),
            "barcode_reviews": len(barcodes["reviews"]),
            "blocking_items": blocking_count,
        },
    }
    plan["plan_hash"] = sha256_json(plan)
    return plan


def _validate_ready_plan(plan: dict[str, Any]) -> None:
    expected_hash = plan.get("plan_hash")
    unsigned = {key: value for key, value in plan.items() if key != "plan_hash"}
    if expected_hash != sha256_json(unsigned):
        raise ImporterError("Plan hash is invalid; regenerate the plan")
    if not plan.get("ready_to_apply"):
        raise ImporterError("Plan contains conflicts or reviews and cannot be applied")


def _plan_records(plan: dict[str, Any], section: str) -> list[dict[str, Any]]:
    identity = "master_product_id" if section == "masters" else "barcode_id"
    result: list[dict[str, Any]] = []
    for key in ("inserts", "updates", "no_ops"):
        for entry in plan[section][key]:
            record = dict(entry["record"])
            record["expected_version"] = entry["expected_version"]
            result.append(record)
    result.sort(key=lambda row: row[identity])
    identities = [str(row.get(identity, "")).lower() for row in result]
    if len(identities) != len(set(identities)):
        raise ImporterError(f"Plan contains duplicate {section} identities")
    return result


def plan_rpc_payload(plan: dict[str, Any]) -> dict[str, Any]:
    """Build the legacy single-request payload used only by focused tests.

    Commercial execution must use the chunked execution manifest so the root
    batch ID is never submitted as a child RPC batch ID.
    """
    _validate_ready_plan(plan)

    return {
        "p_import_batch_id": plan["import_batch_id"],
        "p_dataset_version": plan["dataset_version"],
        "p_masters": _plan_records(plan, "masters"),
        "p_barcodes": _plan_records(plan, "barcodes"),
    }


def _validate_plan_payload_binding(
    plan: dict[str, Any],
    validation_report: dict[str, Any],
) -> None:
    _validate_ready_plan(plan)
    if not validation_report.get("valid"):
        raise ImporterError("Current dataset has blocking validation errors")
    if plan.get("dataset_version") != validation_report.get("dataset_version"):
        raise ImporterError("Plan dataset_version does not match the current dataset")

    expected_masters = sorted(
        (
            _record_for_plan(row, master=True)
            for row in validation_report["normalized_preview"]["masters"]
        ),
        key=stable_json,
    )
    expected_barcodes = sorted(
        (
            _record_for_plan(row, master=False)
            for row in validation_report["normalized_preview"]["barcodes"]
        ),
        key=stable_json,
    )
    actual_masters = sorted(
        ({key: value for key, value in row.items() if key != "expected_version"} for row in _plan_records(plan, "masters")),
        key=stable_json,
    )
    actual_barcodes = sorted(
        ({key: value for key, value in row.items() if key != "expected_version"} for row in _plan_records(plan, "barcodes")),
        key=stable_json,
    )
    if actual_masters != expected_masters:
        raise ImporterError("Plan master payload does not match the current dataset")
    if actual_barcodes != expected_barcodes:
        raise ImporterError("Plan barcode payload does not match the current dataset")


def _file_sha256(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as error:
        raise ImporterError(f"Cannot hash file {path}: {error}") from error


def _execution_payload_hash(
    *,
    dataset_version: str,
    masters: Sequence[dict[str, Any]],
    barcodes: Sequence[dict[str, Any]],
) -> str:
    return sha256_json(
        {
            "dataset_version": dataset_version,
            "masters": list(masters),
            "barcodes": list(barcodes),
        }
    )


def _postgres_jsonb_text(value: Any) -> str:
    """Serialize the importer request domain like PostgreSQL jsonb::text.

    PostgreSQL orders object keys first by UTF-8 byte length and then by their
    byte value, and emits a space after separators. The P1.3 request payload is
    restricted to objects, arrays, strings, booleans, nulls, and integers.
    Unsupported values fail closed instead of approximating server behavior.
    """
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, list):
        return "[" + ", ".join(_postgres_jsonb_text(item) for item in value) + "]"
    if isinstance(value, dict):
        if not all(isinstance(key, str) for key in value):
            raise ImporterError("Remote request hash object keys must be strings")
        keys = sorted(value, key=lambda key: (len(key.encode("utf-8")), key.encode("utf-8")))
        return "{" + ", ".join(
            f"{json.dumps(key, ensure_ascii=False)}: {_postgres_jsonb_text(value[key])}"
            for key in keys
        ) + "}"
    raise ImporterError(
        f"Remote request hash cannot reproduce PostgreSQL jsonb for {type(value).__name__}"
    )


def expected_remote_request_hash(payload: dict[str, Any]) -> str:
    """Return the exact P1.3 import_master_catalog_batch request hash."""
    dataset_version = payload.get("p_dataset_version")
    if not isinstance(dataset_version, str) or not dataset_version.strip(" "):
        raise ImporterError("RPC payload has an invalid dataset_version")
    masters = payload.get("p_masters")
    barcodes = payload.get("p_barcodes")
    if (
        not isinstance(masters, list)
        or not masters
        or not all(isinstance(row, dict) for row in masters)
    ):
        raise ImporterError("RPC payload masters must be a non-empty array of objects")
    if (
        not isinstance(barcodes, list)
        or not barcodes
        or not all(isinstance(row, dict) for row in barcodes)
    ):
        raise ImporterError("RPC payload barcodes must be a non-empty array of objects")
    try:
        ordered_masters = sorted(masters, key=lambda row: row["master_product_id"])
        ordered_barcodes = sorted(barcodes, key=lambda row: row["barcode_id"])
    except KeyError as error:
        raise ImporterError(f"RPC payload is missing an identity required by P1.3: {error}") from error
    request_identity = {
        "dataset_version": dataset_version.strip(" "),
        "masters": ordered_masters,
        "barcodes": ordered_barcodes,
    }
    return hashlib.sha256(_postgres_jsonb_text(request_identity).encode("utf-8")).hexdigest()


def _expected_chunk_operation_counts(
    plan: dict[str, Any],
    chunk: dict[str, Any],
    section: str,
) -> dict[str, int]:
    identity = "master_product_id" if section == "masters" else "barcode_id"
    chunk_ids = set(chunk["master_ids"] if section == "masters" else chunk["barcode_ids"])
    counts = {"inserted": 0, "updated": 0, "no_op": 0}
    classified_ids: set[str] = set()
    for plan_key, response_key in (
        ("inserts", "inserted"),
        ("updates", "updated"),
        ("no_ops", "no_op"),
    ):
        for entry in plan[section][plan_key]:
            entity_id = entry["record"][identity]
            if entity_id in chunk_ids:
                counts[response_key] += 1
                classified_ids.add(entity_id)
    if classified_ids != chunk_ids:
        raise ImporterError(f"Execution chunk contains unclassified {section} identities")
    return counts


def _execution_manifest_binding_view(manifest: dict[str, Any]) -> dict[str, Any]:
    chunks = manifest.get("chunks")
    if not isinstance(chunks, list) or not all(isinstance(chunk, dict) for chunk in chunks):
        raise ImporterError("Execution manifest chunks must be an array of objects")
    return {
        "manifest_version": manifest.get("manifest_version"),
        "root_import_batch_id": manifest.get("root_import_batch_id"),
        "dataset_version": manifest.get("dataset_version"),
        "seed_sha256": manifest.get("seed_sha256"),
        "barcodes_sha256": manifest.get("barcodes_sha256"),
        "snapshot_hash": manifest.get("snapshot_hash"),
        "plan_hash": manifest.get("plan_hash"),
        "chunking_contract": manifest.get("chunking_contract"),
        "max_masters_per_chunk": manifest.get("max_masters_per_chunk"),
        "max_barcodes_per_chunk": manifest.get("max_barcodes_per_chunk"),
        "chunk_count": manifest.get("chunk_count"),
        "masters_total": manifest.get("masters_total"),
        "barcodes_total": manifest.get("barcodes_total"),
        "chunks": [
            {
                "chunk_index": chunk.get("chunk_index"),
                "child_import_batch_id": chunk.get("child_import_batch_id"),
                "master_count": chunk.get("master_count"),
                "barcode_count": chunk.get("barcode_count"),
                "master_ids": chunk.get("master_ids"),
                "barcode_ids": chunk.get("barcode_ids"),
                "payload_hash": chunk.get("payload_hash"),
            }
            for chunk in chunks
        ],
    }


def build_execution_manifest(
    *,
    plan: dict[str, Any],
    seed_sha256: str,
    barcodes_sha256: str,
) -> dict[str, Any]:
    """Build the immutable chunk layout for one logical root import."""
    _validate_ready_plan(plan)
    for label, value in (("seed_sha256", seed_sha256), ("barcodes_sha256", barcodes_sha256)):
        if len(value) != 64 or any(character not in "0123456789abcdef" for character in value.lower()):
            raise ImporterError(f"{label} must be a SHA-256 hex digest")

    try:
        root_uuid = uuid.UUID(str(plan["import_batch_id"]))
    except (KeyError, ValueError, AttributeError) as error:
        raise ImporterError("Plan root import_batch_id must be a UUID") from error
    root_batch_id = str(root_uuid)
    if root_batch_id != str(plan["import_batch_id"]).lower():
        raise ImporterError("Plan root import_batch_id must be canonical")

    masters = _plan_records(plan, "masters")
    barcodes = _plan_records(plan, "barcodes")
    if not masters or not barcodes:
        raise ImporterError("Chunked import requires at least one master and one barcode")

    master_ids = {row["master_product_id"] for row in masters}
    barcodes_by_master: dict[str, list[dict[str, Any]]] = {}
    for barcode in barcodes:
        master_id = str(barcode.get("master_product_id", "")).lower()
        if master_id not in master_ids:
            raise ImporterError(f"Barcode references a master outside the applicable plan: {master_id}")
        barcodes_by_master.setdefault(master_id, []).append(barcode)
    for rows in barcodes_by_master.values():
        rows.sort(key=lambda row: row["barcode_id"])

    grouped: list[tuple[dict[str, Any], list[dict[str, Any]]]] = []
    for master in masters:
        master_id = master["master_product_id"]
        owned_barcodes = barcodes_by_master.get(master_id, [])
        if not owned_barcodes:
            raise ImporterError(f"Applicable master has no barcode in the plan: {master_id}")
        if len(owned_barcodes) > MAX_BARCODES_PER_CHUNK:
            raise ImporterError(
                f"Master {master_id} has {len(owned_barcodes)} barcodes and cannot fit in one RPC chunk"
            )
        grouped.append((master, owned_barcodes))

    chunk_groups: list[list[tuple[dict[str, Any], list[dict[str, Any]]]]] = []
    current: list[tuple[dict[str, Any], list[dict[str, Any]]]] = []
    current_barcode_count = 0
    for group in grouped:
        group_barcode_count = len(group[1])
        if current and (
            len(current) + 1 > MAX_MASTERS_PER_CHUNK
            or current_barcode_count + group_barcode_count > MAX_BARCODES_PER_CHUNK
        ):
            chunk_groups.append(current)
            current = []
            current_barcode_count = 0
        current.append(group)
        current_barcode_count += group_barcode_count
    if current:
        chunk_groups.append(current)

    chunks: list[dict[str, Any]] = []
    for index, groups in enumerate(chunk_groups, start=1):
        chunk_masters = [group[0] for group in groups]
        chunk_barcodes = [barcode for group in groups for barcode in group[1]]
        payload_hash = _execution_payload_hash(
            dataset_version=plan["dataset_version"],
            masters=chunk_masters,
            barcodes=chunk_barcodes,
        )
        child_batch_id = str(
            uuid.uuid5(
                root_uuid,
                stable_json(
                    {
                        "plan_hash": plan["plan_hash"],
                        "chunk_index": index,
                        "payload_hash": payload_hash,
                    }
                ),
            )
        )
        chunks.append(
            {
                "chunk_index": index,
                "child_import_batch_id": child_batch_id,
                "master_count": len(chunk_masters),
                "barcode_count": len(chunk_barcodes),
                "master_ids": [row["master_product_id"] for row in chunk_masters],
                "barcode_ids": [row["barcode_id"] for row in chunk_barcodes],
                "payload_hash": payload_hash,
                "status": "pending",
                "attempts": 0,
            }
        )

    manifest: dict[str, Any] = {
        "manifest_version": EXECUTION_MANIFEST_VERSION,
        "root_import_batch_id": root_batch_id,
        "dataset_version": plan["dataset_version"],
        "seed_sha256": seed_sha256.lower(),
        "barcodes_sha256": barcodes_sha256.lower(),
        "snapshot_hash": plan["snapshot_hash"],
        "plan_hash": plan["plan_hash"],
        "chunking_contract": CHUNKING_CONTRACT,
        "max_masters_per_chunk": MAX_MASTERS_PER_CHUNK,
        "max_barcodes_per_chunk": MAX_BARCODES_PER_CHUNK,
        "chunk_count": len(chunks),
        "masters_total": len(masters),
        "barcodes_total": len(barcodes),
        "status": "prepared",
        "chunks": chunks,
    }
    manifest["manifest_hash"] = sha256_json(_execution_manifest_binding_view(manifest))
    return manifest


def validate_execution_manifest(
    manifest: dict[str, Any],
    *,
    plan: dict[str, Any],
    seed_sha256: str,
    barcodes_sha256: str,
) -> None:
    expected = build_execution_manifest(
        plan=plan,
        seed_sha256=seed_sha256,
        barcodes_sha256=barcodes_sha256,
    )
    actual_hash = sha256_json(_execution_manifest_binding_view(manifest))
    if manifest.get("manifest_hash") != actual_hash:
        raise ImporterError("Execution manifest hash is invalid")

    for field in (
        "manifest_version",
        "root_import_batch_id",
        "dataset_version",
        "seed_sha256",
        "barcodes_sha256",
        "snapshot_hash",
        "plan_hash",
        "chunking_contract",
        "max_masters_per_chunk",
        "max_barcodes_per_chunk",
        "chunk_count",
        "masters_total",
        "barcodes_total",
    ):
        if manifest.get(field) != expected.get(field):
            raise ImporterError(f"Execution manifest binding mismatch: {field}")
    if _execution_manifest_binding_view(manifest)["chunks"] != _execution_manifest_binding_view(expected)["chunks"]:
        raise ImporterError("Execution manifest chunk layout does not match the current plan")

    chunks = manifest["chunks"]
    if manifest.get("status") not in {"prepared", "running", "failed", "completed"}:
        raise ImporterError("Execution manifest contains an invalid execution status")
    for chunk in chunks:
        if chunk.get("status") not in {"pending", "in_flight", "failed", "completed"}:
            raise ImporterError("Execution manifest contains an invalid chunk status")
        attempts = chunk.get("attempts", 0)
        if not isinstance(attempts, int) or attempts < 0:
            raise ImporterError("Execution manifest contains an invalid attempt count")
        if chunk.get("status") == "completed":
            remote_result = chunk.get("remote_result")
            if not isinstance(remote_result, dict):
                raise ImporterError("Completed execution chunk is missing its remote result")
            summary = _safe_import_result_summary(remote_result)
            if summary["import_batch_id"] != chunk.get("child_import_batch_id"):
                raise ImporterError("Completed execution chunk has a mismatched remote result")
            if summary["dataset_version"] != manifest.get("dataset_version"):
                raise ImporterError("Completed execution chunk has a mismatched dataset_version")
            payload = _payload_for_execution_chunk(plan, chunk)
            if summary["request_hash"] != expected_remote_request_hash(payload):
                raise ImporterError("Completed execution chunk has a mismatched request_hash")
            expected_master_counts = _expected_chunk_operation_counts(plan, chunk, "masters")
            expected_barcode_counts = _expected_chunk_operation_counts(plan, chunk, "barcodes")
            if summary["masters"] != expected_master_counts:
                raise ImporterError("Completed execution chunk has inconsistent master counts")
            if summary["barcodes"] != expected_barcode_counts:
                raise ImporterError("Completed execution chunk has inconsistent barcode counts")


def prepare_execution_manifest(
    *,
    plan: dict[str, Any],
    snapshot: dict[str, Any],
    validation_report: dict[str, Any],
    masters_path: Path,
    barcodes_path: Path,
    output_path: Path,
) -> tuple[dict[str, Any], bool]:
    _validate_plan_payload_binding(plan, validation_report)
    if plan.get("snapshot_hash") != sha256_json(parse_snapshot(snapshot)):
        raise ImporterError("Plan snapshot_hash does not match the supplied snapshot")
    seed_sha256 = _file_sha256(masters_path)
    barcodes_sha256 = _file_sha256(barcodes_path)
    expected = build_execution_manifest(
        plan=plan,
        seed_sha256=seed_sha256,
        barcodes_sha256=barcodes_sha256,
    )
    if output_path.exists():
        existing = read_json(output_path)
        validate_execution_manifest(
            existing,
            plan=plan,
            seed_sha256=seed_sha256,
            barcodes_sha256=barcodes_sha256,
        )
        return existing, False
    write_json_atomic(output_path, expected)
    return expected, True


def _payload_for_execution_chunk(plan: dict[str, Any], chunk: dict[str, Any]) -> dict[str, Any]:
    masters_by_id = {row["master_product_id"]: row for row in _plan_records(plan, "masters")}
    barcodes_by_id = {row["barcode_id"]: row for row in _plan_records(plan, "barcodes")}
    try:
        masters = [masters_by_id[master_id] for master_id in chunk["master_ids"]]
        barcodes = [barcodes_by_id[barcode_id] for barcode_id in chunk["barcode_ids"]]
    except KeyError as error:
        raise ImporterError(f"Execution chunk references an entity outside the plan: {error}") from error
    payload_hash = _execution_payload_hash(
        dataset_version=plan["dataset_version"],
        masters=masters,
        barcodes=barcodes,
    )
    if payload_hash != chunk.get("payload_hash"):
        raise ImporterError("Execution chunk payload hash does not match the plan")
    return {
        "p_import_batch_id": chunk["child_import_batch_id"],
        "p_dataset_version": plan["dataset_version"],
        "p_masters": masters,
        "p_barcodes": barcodes,
    }


def _safe_import_result_summary(result: dict[str, Any]) -> dict[str, Any]:
    status = result.get("status")
    batch_id = str(result.get("import_batch_id", "")).lower()
    if status not in {"applied", "already_applied"}:
        raise ImporterError(f"Import RPC returned unexpected status: {status!r}")
    try:
        canonical_batch_id = str(uuid.UUID(batch_id))
    except ValueError as error:
        raise ImporterError("Import RPC returned an invalid import_batch_id") from error
    if canonical_batch_id != batch_id:
        raise ImporterError("Import RPC returned a non-canonical import_batch_id")
    request_hash = result.get("request_hash")
    if (
        not isinstance(request_hash, str)
        or len(request_hash) != 64
        or any(character not in "0123456789abcdef" for character in request_hash.lower())
    ):
        raise ImporterError("Import RPC returned an invalid request_hash")

    summary: dict[str, Any] = {
        "status": status,
        "import_batch_id": batch_id,
        "dataset_version": result.get("dataset_version"),
        "request_hash": request_hash.lower(),
    }
    for section in ("masters", "barcodes"):
        values = result.get(section)
        if not isinstance(values, dict):
            raise ImporterError(f"Import RPC result is missing {section} counts")
        required_keys = ("inserted", "updated", "no_op")
        missing = [key for key in required_keys if key not in values]
        if missing:
            raise ImporterError(
                f"Import RPC result is missing required {section} counts: {', '.join(missing)}"
            )
        summary[section] = {}
        for key in required_keys:
            value = values[key]
            if isinstance(value, bool) or not isinstance(value, int):
                raise ImporterError(f"Import RPC returned invalid {section}.{key} count")
            summary[section][key] = value
        if any(value < 0 for value in summary[section].values()):
            raise ImporterError(f"Import RPC returned negative {section} counts")
    return summary


def apply_execution_manifest(
    *,
    plan: dict[str, Any],
    manifest: dict[str, Any],
    manifest_path: Path,
    seed_sha256: str,
    barcodes_sha256: str,
    rpc: Callable[[str, dict[str, Any]], dict[str, Any]],
    after_rpc: Callable[[int, dict[str, Any]], None] | None = None,
) -> dict[str, Any]:
    """Apply pending chunks sequentially, persisting progress after each RPC."""
    validate_execution_manifest(
        manifest,
        plan=plan,
        seed_sha256=seed_sha256,
        barcodes_sha256=barcodes_sha256,
    )
    working = deepcopy(manifest)
    working["status"] = "running"
    write_json_atomic(manifest_path, working)

    for chunk in working["chunks"]:
        if chunk["status"] == "completed":
            continue
        payload = _payload_for_execution_chunk(plan, chunk)
        expected_request_hash = expected_remote_request_hash(payload)
        expected_master_counts = _expected_chunk_operation_counts(plan, chunk, "masters")
        expected_barcode_counts = _expected_chunk_operation_counts(plan, chunk, "barcodes")
        chunk["status"] = "in_flight"
        chunk["attempts"] = int(chunk.get("attempts", 0)) + 1
        chunk.pop("last_error", None)
        write_json_atomic(manifest_path, working)
        try:
            result = rpc("import_master_catalog_batch", payload)
            summary = _safe_import_result_summary(result)
            if summary["import_batch_id"] != chunk["child_import_batch_id"]:
                raise ImporterError("Import RPC returned a different child import_batch_id")
            if summary["dataset_version"] != plan["dataset_version"]:
                raise ImporterError("Import RPC returned a different dataset_version")
            if summary["request_hash"] != expected_request_hash:
                raise ImporterError("Import RPC returned a different request_hash")
            if summary["masters"] != expected_master_counts:
                raise ImporterError("Import RPC returned inconsistent master counts")
            if summary["barcodes"] != expected_barcode_counts:
                raise ImporterError("Import RPC returned inconsistent barcode counts")
            if after_rpc is not None:
                after_rpc(chunk["chunk_index"], summary)
        except Exception as error:
            chunk["status"] = "failed"
            chunk["last_error"] = str(error)
            working["status"] = "failed"
            write_json_atomic(manifest_path, working)
            if isinstance(error, ImporterError):
                raise
            raise ImporterError(
                f"Chunk {chunk['chunk_index']} failed; execution stopped: {error}"
            ) from error
        chunk["status"] = "completed"
        chunk["remote_result"] = summary
        write_json_atomic(manifest_path, working)

    working["status"] = "completed"
    write_json_atomic(manifest_path, working)
    return {
        "execution_version": 1,
        "root_import_batch_id": working["root_import_batch_id"],
        "status": "completed",
        "chunk_count": working["chunk_count"],
        "completed_chunks": sum(chunk["status"] == "completed" for chunk in working["chunks"]),
        "masters_total": working["masters_total"],
        "barcodes_total": working["barcodes_total"],
        "manifest_hash": working["manifest_hash"],
    }


def verify_import_plan(plan: dict[str, Any], snapshot: dict[str, Any]) -> dict[str, Any]:
    snapshot = parse_snapshot(snapshot)
    remote_masters = {str(row["id"]).lower(): row for row in snapshot["masters"]}
    remote_barcodes = {str(row["id"]).lower(): row for row in snapshot["global_barcodes"]}
    errors: list[dict[str, str]] = []

    for section, remote_rows, matcher, identity in (
        ("masters", remote_masters, _remote_master_matches, "master_product_id"),
        ("barcodes", remote_barcodes, _remote_barcode_matches, "barcode_id"),
    ):
        for key in ("inserts", "updates", "no_ops"):
            for entry in plan[section][key]:
                desired = entry["record"]
                entity_id = desired[identity]
                remote = remote_rows.get(entity_id)
                if remote is None or remote.get("deleted_at") is not None:
                    errors.append({"entity": section, "id": entity_id, "reason": "missing_or_tombstoned"})
                elif not matcher(remote, desired):
                    errors.append({"entity": section, "id": entity_id, "reason": "canonical_payload_mismatch"})

    active_global = [
        row for row in snapshot["global_barcodes"]
        if row.get("deleted_at") is None and row.get("status") == "active"
    ]
    code_counts: dict[str, int] = {}
    primary_counts: dict[str, int] = {}
    for row in active_global:
        code = catalog_tool.normalize_barcode(row.get("barcode"))
        code_counts[code] = code_counts.get(code, 0) + 1
        if row.get("is_primary"):
            master_id = str(row.get("master_product_id", "")).lower()
            primary_counts[master_id] = primary_counts.get(master_id, 0) + 1
    for code, count in sorted(code_counts.items()):
        if count > 1:
            errors.append({"entity": "barcodes", "id": code, "reason": "duplicate_active_global_code"})
    for master_id, count in sorted(primary_counts.items()):
        if count > 1:
            errors.append({"entity": "barcodes", "id": master_id, "reason": "multiple_active_primaries"})

    report = {
        "verification_version": 1,
        "import_batch_id": plan["import_batch_id"],
        "dataset_version": plan["dataset_version"],
        "valid": not errors,
        "verified_masters": sum(len(plan["masters"][key]) for key in ("inserts", "updates", "no_ops")),
        "verified_barcodes": sum(len(plan["barcodes"][key]) for key in ("inserts", "updates", "no_ops")),
        "errors": errors,
    }
    report["report_hash"] = sha256_json(report)
    return report


def _service_role_environment() -> tuple[str, str]:
    url = os.environ.get("SUPABASE_URL", "").strip().rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not url or not key:
        raise ImporterError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY environment variables are required")
    if not url.startswith("https://") and not url.startswith("http://127.0.0.1") and not url.startswith("http://localhost"):
        raise ImporterError("SUPABASE_URL must use HTTPS except for localhost")
    return url, key


def rpc_call(function_name: str, payload: dict[str, Any]) -> dict[str, Any]:
    url, key = _service_role_environment()
    request = urllib.request.Request(
        f"{url}/rest/v1/rpc/{function_name}",
        data=json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8"),
        headers={
            "apikey": key,
            "authorization": f"Bearer {key}",
            "content-type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=DEFAULT_HTTP_TIMEOUT_SECONDS) as response:
            result = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        try:
            details = json.loads(error.read().decode("utf-8"))
            safe_message = details.get("message") or details.get("code") or f"HTTP {error.code}"
        except (UnicodeError, json.JSONDecodeError):
            safe_message = f"HTTP {error.code}"
        raise ImporterError(f"Supabase RPC {function_name} failed: {safe_message}") from error
    except (OSError, urllib.error.URLError, UnicodeError, json.JSONDecodeError) as error:
        raise ImporterError(f"Supabase RPC {function_name} failed without exposing credentials: {error}") from error
    if not isinstance(result, dict):
        raise ImporterError(f"Supabase RPC {function_name} returned a non-object response")
    return result


def _path(value: str) -> Path:
    return Path(value).expanduser().resolve()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    snapshot = commands.add_parser("snapshot", help="Export a service-role read-only catalog snapshot")
    snapshot.add_argument("--output", type=_path, required=True)

    plan = commands.add_parser("plan", help="Build a deterministic import plan from validated CSV files")
    plan.add_argument("--against", type=_path, required=True)
    plan.add_argument("--import-batch-id", required=True)
    plan.add_argument("--masters", type=_path, default=catalog_tool.DEFAULT_MASTERS)
    plan.add_argument("--barcodes", type=_path, default=catalog_tool.DEFAULT_BARCODES)
    plan.add_argument("--manifest", type=_path, default=catalog_tool.DEFAULT_MANIFEST)
    plan.add_argument("--vocabularies", type=_path, default=catalog_tool.DEFAULT_CONFIG)
    plan.add_argument("--output", type=_path, required=True)

    prepare_apply = commands.add_parser(
        "prepare-apply",
        help="Prepare the durable chunk manifest without Hosted access",
    )
    prepare_apply.add_argument("--plan", type=_path, required=True)
    prepare_apply.add_argument("--against", type=_path, required=True)
    prepare_apply.add_argument("--masters", type=_path, default=catalog_tool.DEFAULT_MASTERS)
    prepare_apply.add_argument("--barcodes", type=_path, default=catalog_tool.DEFAULT_BARCODES)
    prepare_apply.add_argument("--manifest", type=_path, default=catalog_tool.DEFAULT_MANIFEST)
    prepare_apply.add_argument("--vocabularies", type=_path, default=catalog_tool.DEFAULT_CONFIG)
    prepare_apply.add_argument("--output", type=_path, required=True)

    apply_command = commands.add_parser(
        "apply",
        help="Resume pending chunks from a reviewed execution manifest",
    )
    apply_command.add_argument("--plan", type=_path, required=True)
    apply_command.add_argument("--against", type=_path, required=True)
    apply_command.add_argument("--execution-manifest", type=_path, required=True)
    apply_command.add_argument("--masters", type=_path, default=catalog_tool.DEFAULT_MASTERS)
    apply_command.add_argument("--barcodes", type=_path, default=catalog_tool.DEFAULT_BARCODES)
    apply_command.add_argument("--manifest", type=_path, default=catalog_tool.DEFAULT_MANIFEST)
    apply_command.add_argument("--vocabularies", type=_path, default=catalog_tool.DEFAULT_CONFIG)
    apply_command.add_argument("--confirm-import-batch-id", required=True)
    apply_command.add_argument("--output", type=_path, required=True)

    verify = commands.add_parser("verify", help="Verify a plan against a post-import snapshot")
    verify.add_argument("--plan", type=_path, required=True)
    verify.add_argument("--against", type=_path, required=True)
    verify.add_argument("--output", type=_path, required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "snapshot":
            result = parse_snapshot(rpc_call("export_master_catalog_snapshot", {}))
            write_json(args.output, result)
            print(f"Snapshot written: {args.output} (masters={len(result['masters'])}, barcodes={len(result['global_barcodes'])})")
            return 0

        if args.command == "plan":
            report = catalog_tool.validate_dataset(
                masters_path=args.masters,
                barcodes_path=args.barcodes,
                manifest_path=args.manifest,
                vocabularies_path=args.vocabularies,
            )
            result = build_import_plan(
                validation_report=report,
                snapshot=load_snapshot(args.against),
                import_batch_id=args.import_batch_id,
            )
            write_json(args.output, result)
            print(f"Plan written: {args.output} (ready_to_apply={str(result['ready_to_apply']).lower()})")
            return 0 if result["ready_to_apply"] else 1

        if args.command == "prepare-apply":
            plan = read_json(args.plan)
            report = catalog_tool.validate_dataset(
                masters_path=args.masters,
                barcodes_path=args.barcodes,
                manifest_path=args.manifest,
                vocabularies_path=args.vocabularies,
            )
            result, created = prepare_execution_manifest(
                plan=plan,
                snapshot=load_snapshot(args.against),
                validation_report=report,
                masters_path=args.masters,
                barcodes_path=args.barcodes,
                output_path=args.output,
            )
            max_masters = max(chunk["master_count"] for chunk in result["chunks"])
            max_barcodes = max(chunk["barcode_count"] for chunk in result["chunks"])
            print(
                f"Execution manifest {'created' if created else 'verified'}: {args.output} "
                f"(chunks={result['chunk_count']}, masters={result['masters_total']}, "
                f"barcodes={result['barcodes_total']}, max_masters={max_masters}, "
                f"max_barcodes={max_barcodes})"
            )
            return 0

        if args.command == "apply":
            plan = read_json(args.plan)
            if args.confirm_import_batch_id.lower() != str(plan.get("import_batch_id", "")).lower():
                raise ImporterError("Confirmation import_batch_id does not match the plan")
            report = catalog_tool.validate_dataset(
                masters_path=args.masters,
                barcodes_path=args.barcodes,
                manifest_path=args.manifest,
                vocabularies_path=args.vocabularies,
            )
            _validate_plan_payload_binding(plan, report)
            if plan.get("snapshot_hash") != sha256_json(load_snapshot(args.against)):
                raise ImporterError("Plan snapshot_hash does not match the supplied snapshot")
            result = apply_execution_manifest(
                plan=plan,
                manifest=read_json(args.execution_manifest),
                manifest_path=args.execution_manifest,
                seed_sha256=_file_sha256(args.masters),
                barcodes_sha256=_file_sha256(args.barcodes),
                rpc=rpc_call,
            )
            write_json_atomic(args.output, result)
            print(
                f"Import execution result written: {args.output} "
                f"(status={result.get('status')}, chunks={result.get('completed_chunks')})"
            )
            return 0

        plan = read_json(args.plan)
        result = verify_import_plan(plan, load_snapshot(args.against))
        write_json(args.output, result)
        print(f"Verification written: {args.output} (valid={str(result['valid']).lower()})")
        return 0 if result["valid"] else 1
    except (ImporterError, catalog_tool.CatalogToolError) as error:
        print(f"IMPORTER ERROR: {error}", file=sys.stderr)
        return 2
    except OSError as error:
        print(f"I/O ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
