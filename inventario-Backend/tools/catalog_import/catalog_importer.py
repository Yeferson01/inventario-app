#!/usr/bin/env python3
"""P1.3 remote-aware master catalog planner and administrative RPC client."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request
import uuid
from decimal import Decimal, InvalidOperation
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any, Sequence

import catalog_tool


IMPORTER_VERSION = "1.0.0"
PLAN_VERSION = 1
SNAPSHOT_VERSION = 1
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


def plan_rpc_payload(plan: dict[str, Any]) -> dict[str, Any]:
    expected_hash = plan.get("plan_hash")
    unsigned = {key: value for key, value in plan.items() if key != "plan_hash"}
    if expected_hash != sha256_json(unsigned):
        raise ImporterError("Plan hash is invalid; regenerate the plan")
    if not plan.get("ready_to_apply"):
        raise ImporterError("Plan contains conflicts or reviews and cannot be applied")

    def records(section: str) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = []
        for key in ("inserts", "updates", "no_ops"):
            for entry in plan[section][key]:
                record = dict(entry["record"])
                record["expected_version"] = entry["expected_version"]
                result.append(record)
        identity = "master_product_id" if section == "masters" else "barcode_id"
        return sorted(result, key=lambda row: row[identity])

    return {
        "p_import_batch_id": plan["import_batch_id"],
        "p_dataset_version": plan["dataset_version"],
        "p_masters": records("masters"),
        "p_barcodes": records("barcodes"),
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

    apply_command = commands.add_parser("apply", help="Apply a reviewed plan through the transactional RPC")
    apply_command.add_argument("--plan", type=_path, required=True)
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

        if args.command == "apply":
            plan = read_json(args.plan)
            if args.confirm_import_batch_id.lower() != str(plan.get("import_batch_id", "")).lower():
                raise ImporterError("Confirmation import_batch_id does not match the plan")
            payload = plan_rpc_payload(plan)
            result = rpc_call("import_master_catalog_batch", payload)
            write_json(args.output, result)
            print(f"Import result written: {args.output} (status={result.get('status')})")
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
