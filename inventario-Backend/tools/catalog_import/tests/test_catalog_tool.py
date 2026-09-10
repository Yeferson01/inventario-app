from __future__ import annotations

import csv
import io
import json
import socket
import sys
import tempfile
import time
import unittest
import uuid
from copy import deepcopy
from pathlib import Path
from unittest import mock


TOOL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL_DIR))

import catalog_tool as tool  # noqa: E402
import catalog_importer as importer  # noqa: E402


FIXTURES = Path(__file__).resolve().parent / "fixtures"
CASES = json.loads((FIXTURES / "catalog_cases.json").read_text(encoding="utf-8"))


class CatalogToolTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def _valid_rows(self) -> tuple[dict[str, str], dict[str, str]]:
        return deepcopy(CASES["valid_master"]), deepcopy(CASES["valid_primary_barcode"])

    def _write_csv(self, path: Path, headers: list[str], rows: list[dict[str, str]]) -> None:
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=headers, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)

    @staticmethod
    def _csv_bytes(headers: list[str], rows: list[dict[str, str]]) -> bytes:
        buffer = io.StringIO(newline="")
        writer = csv.DictWriter(buffer, fieldnames=headers, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
        return buffer.getvalue().encode("utf-8")

    def _report(
        self,
        masters: list[dict[str, str]],
        barcodes: list[dict[str, str]],
        *,
        master_headers: list[str] | None = None,
    ) -> dict[str, object]:
        masters_path = self.root / "master_catalog_seed.csv"
        barcodes_path = self.root / "master_catalog_barcodes.csv"
        self._write_csv(masters_path, master_headers or tool.MASTER_HEADERS, masters)
        self._write_csv(barcodes_path, tool.BARCODE_HEADERS, barcodes)
        return tool.validate_dataset(
            masters_path=masters_path,
            barcodes_path=barcodes_path,
            manifest_path=tool.DEFAULT_MANIFEST,
            vocabularies_path=tool.DEFAULT_CONFIG,
        )

    def _sync(
        self,
        masters: list[dict[str, str]],
        barcodes: list[dict[str, str]],
        *,
        dry_run: bool = False,
    ) -> tuple[dict[str, object], Path, Path]:
        masters_path = self.root / "master_catalog_seed.csv"
        barcodes_path = self.root / "master_catalog_barcodes.csv"
        self._write_csv(masters_path, tool.MASTER_HEADERS, masters)
        self._write_csv(barcodes_path, tool.BARCODE_HEADERS, barcodes)
        report = tool.sync_primary_barcodes(
            masters_path=masters_path,
            barcodes_path=barcodes_path,
            manifest_path=tool.DEFAULT_MANIFEST,
            vocabularies_path=tool.DEFAULT_CONFIG,
            backup_dir=self.root / "backups",
            dry_run=dry_run,
        )
        return report, masters_path, barcodes_path

    def _prune(
        self,
        masters: list[dict[str, str]],
        barcodes: list[dict[str, str]],
        *,
        dry_run: bool = False,
    ) -> tuple[dict[str, object], Path, Path, Path]:
        masters_path = self.root / "master_catalog_seed.csv"
        barcodes_path = self.root / "master_catalog_barcodes.csv"
        rejected_path = self.root / "reports" / "rejected_invalid_barcode_rows.csv"
        self._write_csv(masters_path, tool.MASTER_HEADERS, masters)
        self._write_csv(barcodes_path, tool.BARCODE_HEADERS, barcodes)
        report = tool.prune_invalid_barcode_masters(
            masters_path=masters_path,
            barcodes_path=barcodes_path,
            rejected_report_path=rejected_path,
            manifest_path=tool.DEFAULT_MANIFEST,
            vocabularies_path=tool.DEFAULT_CONFIG,
            backup_dir=self.root / "backups",
            expected_count=1,
            dry_run=dry_run,
        )
        return report, masters_path, barcodes_path, rejected_path

    def _exact_duplicate_fixture(
        self,
    ) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
        first, first_barcode = self._valid_rows()
        duplicate = deepcopy(first)
        duplicate.update(
            master_product_id="22222222-2222-4222-8222-222222222222",
            primary_barcode="96385074",
            barcode_type="ean8",
        )
        duplicate_barcode = deepcopy(first_barcode)
        duplicate_barcode.update(
            barcode_id="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2",
            master_product_id=duplicate["master_product_id"],
            barcode=duplicate["primary_barcode"],
            barcode_type=duplicate["barcode_type"],
        )
        retained = deepcopy(first)
        retained.update(
            master_product_id="33333333-3333-4333-8333-333333333333",
            primary_barcode=self._ean13(999),
            name="Producto sin duplicado exacto",
        )
        retained_barcode = deepcopy(first_barcode)
        retained_barcode.update(
            barcode_id="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3",
            master_product_id=retained["master_product_id"],
            barcode=retained["primary_barcode"],
        )
        return [first, duplicate, retained], [first_barcode, duplicate_barcode, retained_barcode]

    def _exact_prune(
        self,
        masters: list[dict[str, str]],
        barcodes: list[dict[str, str]],
        *,
        dry_run: bool = False,
        expected_barcode_count: int = 2,
    ) -> tuple[dict[str, object], Path, Path, Path, Path]:
        masters_path = self.root / "master_catalog_seed.csv"
        barcodes_path = self.root / "master_catalog_barcodes.csv"
        rejected_masters = self.root / "reports" / "rejected_exact_masters.csv"
        rejected_barcodes = self.root / "reports" / "rejected_exact_barcodes.csv"
        self._write_csv(masters_path, tool.MASTER_HEADERS, masters)
        self._write_csv(barcodes_path, tool.BARCODE_HEADERS, barcodes)
        report = tool.prune_exact_semantic_duplicates(
            masters_path=masters_path,
            barcodes_path=barcodes_path,
            rejected_masters_path=rejected_masters,
            rejected_barcodes_path=rejected_barcodes,
            manifest_path=tool.DEFAULT_MANIFEST,
            vocabularies_path=tool.DEFAULT_CONFIG,
            backup_dir=self.root / "backups",
            expected_group_count=1,
            expected_master_count=2,
            expected_barcode_count=expected_barcode_count,
            dry_run=dry_run,
        )
        return report, masters_path, barcodes_path, rejected_masters, rejected_barcodes

    def _preflight_fixture(
        self,
    ) -> tuple[list[dict[str, str]], list[dict[str, str]], dict[str, object], dict[str, object]]:
        review, review_barcode = self._valid_rows()
        conflict = deepcopy(review)
        conflict.update(
            master_product_id="22222222-2222-4222-8222-222222222222",
            primary_barcode=self._ean13(902),
            name="Producto con conflicto Hosted",
        )
        conflict_barcode = deepcopy(review_barcode)
        conflict_barcode.update(
            barcode_id="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2",
            master_product_id=conflict["master_product_id"],
            barcode=conflict["primary_barcode"],
        )
        retained = deepcopy(review)
        retained.update(
            master_product_id="33333333-3333-4333-8333-333333333333",
            primary_barcode=self._ean13(903),
            name="Producto conservado",
        )
        retained_barcode = deepcopy(review_barcode)
        retained_barcode.update(
            barcode_id="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3",
            master_product_id=retained["master_product_id"],
            barcode=retained["primary_barcode"],
        )

        def entry(classification: str, reason: str, record: dict[str, str]) -> dict[str, object]:
            return {
                "classification": classification,
                "expected_version": None,
                "reason": reason,
                "record": deepcopy(record),
            }

        plan: dict[str, object] = {
            "plan_version": 1,
            "import_batch_id": "44444444-4444-4444-8444-444444444444",
            "masters": {
                "inserts": [entry("INSERT", "insert", retained)],
                "updates": [],
                "no_ops": [],
                "reviews": [entry("REVIEW", "near semantic duplicate exists inside the dataset", review)],
                "conflicts": [entry("CONFLICT", "primary barcode is active under another master", conflict)],
            },
            "barcodes": {
                "inserts": [entry("INSERT", "insert", retained_barcode)],
                "updates": [],
                "no_ops": [],
                "reviews": [entry("REVIEW", "owning master requires review", review_barcode)],
                "conflicts": [
                    entry(
                        "CONFLICT",
                        "normalized barcode is active under another barcode identity",
                        conflict_barcode,
                    )
                ],
            },
        }
        snapshot: dict[str, object] = {
            "snapshot_version": 1,
            "masters": [],
            "global_barcodes": [
                {
                    "id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
                    "master_product_id": "55555555-5555-4555-8555-555555555555",
                    "barcode": conflict["primary_barcode"],
                    "scope": "global",
                    "status": "active",
                    "deleted_at": None,
                }
            ],
        }
        plan["snapshot_hash"] = importer.sha256_json(importer.parse_snapshot(snapshot))
        plan["plan_hash"] = importer.sha256_json(plan)
        return [review, conflict, retained], [review_barcode, conflict_barcode, retained_barcode], plan, snapshot

    def _preflight_prune(
        self,
        masters: list[dict[str, str]],
        barcodes: list[dict[str, str]],
        plan: dict[str, object],
        snapshot: dict[str, object],
        *,
        dry_run: bool = False,
    ) -> tuple[dict[str, object], Path, Path, list[Path]]:
        masters_path = self.root / "master_catalog_seed.csv"
        barcodes_path = self.root / "master_catalog_barcodes.csv"
        plan_path = self.root / "plan.json"
        snapshot_path = self.root / "snapshot.json"
        reports = [
            self.root / "reports" / "review_masters.csv",
            self.root / "reports" / "review_barcodes.csv",
            self.root / "reports" / "conflict_masters.csv",
            self.root / "reports" / "conflict_barcodes.csv",
        ]
        self._write_csv(masters_path, tool.MASTER_HEADERS, masters)
        self._write_csv(barcodes_path, tool.BARCODE_HEADERS, barcodes)
        plan_path.write_text(json.dumps(plan), encoding="utf-8")
        snapshot_path.write_text(json.dumps(snapshot), encoding="utf-8")
        report = tool.prune_preflight_blockers(
            masters_path=masters_path,
            barcodes_path=barcodes_path,
            plan_path=plan_path,
            snapshot_path=snapshot_path,
            rejected_review_masters_path=reports[0],
            rejected_review_barcodes_path=reports[1],
            rejected_conflict_masters_path=reports[2],
            rejected_conflict_barcodes_path=reports[3],
            backup_dir=self.root / "backups",
            expected_review_count=1,
            expected_conflict_count=1,
            dry_run=dry_run,
        )
        return report, masters_path, barcodes_path, reports

    @staticmethod
    def _ean13(index: int) -> str:
        payload = f"{200000000000 + index:012d}"
        total = sum(
            int(digit) * (3 if offset % 2 == 1 else 1)
            for offset, digit in enumerate(reversed(payload), start=1)
        )
        return payload + str((10 - total % 10) % 10)

    @staticmethod
    def _codes(report: dict[str, object], key: str = "blocking_errors") -> set[str]:
        return {issue["code"] for issue in report[key]}  # type: ignore[index]

    def test_01_valid_dataset_passes(self) -> None:
        report = tool.validate_dataset(
            masters_path=FIXTURES / "valid" / "master_catalog_seed.csv",
            barcodes_path=FIXTURES / "valid" / "master_catalog_barcodes.csv",
            manifest_path=tool.DEFAULT_MANIFEST,
            vocabularies_path=tool.DEFAULT_CONFIG,
        )
        self.assertTrue(report["valid"])
        self.assertEqual(report["blocking_error_count"], 0)

    def test_02_allocate_ids_preserves_existing_ids(self) -> None:
        master, barcode = self._valid_rows()
        masters = self.root / "masters.csv"
        barcodes = self.root / "barcodes.csv"
        self._write_csv(masters, tool.MASTER_HEADERS, [master])
        self._write_csv(barcodes, tool.BARCODE_HEADERS, [barcode])
        result = tool.allocate_ids(masters_path=masters, barcodes_path=barcodes)
        self.assertEqual(result["allocated_master_product_ids"], 0)
        self.assertEqual(result["allocated_barcode_ids"], 0)
        self.assertIn(master["master_product_id"], masters.read_text(encoding="utf-8"))
        self.assertIn(barcode["barcode_id"], barcodes.read_text(encoding="utf-8"))

    def test_03_explicit_uuid_allocation_is_persisted_and_idempotent(self) -> None:
        master, barcode = self._valid_rows()
        master["master_product_id"] = ""
        barcode["master_product_id"] = ""
        barcode["barcode_id"] = ""
        masters = self.root / "masters.csv"
        barcodes = self.root / "barcodes.csv"
        self._write_csv(masters, tool.MASTER_HEADERS, [master])
        self._write_csv(barcodes, tool.BARCODE_HEADERS, [barcode])

        first = tool.allocate_ids(masters_path=masters, barcodes_path=barcodes)
        second = tool.allocate_ids(masters_path=masters, barcodes_path=barcodes)
        with masters.open(encoding="utf-8", newline="") as handle:
            allocated_master = next(csv.DictReader(handle))
        with barcodes.open(encoding="utf-8", newline="") as handle:
            allocated_barcode = next(csv.DictReader(handle))

        self.assertEqual(first, {
            "allocated_master_product_ids": 1,
            "allocated_barcode_ids": 1,
            "linked_barcode_master_ids": 1,
        })
        self.assertEqual(second, {
            "allocated_master_product_ids": 0,
            "allocated_barcode_ids": 0,
            "linked_barcode_master_ids": 0,
        })
        self.assertTrue(tool.is_valid_uuid(allocated_master["master_product_id"]))
        self.assertTrue(tool.is_valid_uuid(allocated_barcode["barcode_id"]))
        self.assertEqual(allocated_barcode["master_product_id"], allocated_master["master_product_id"])

    def test_04_leading_zero_barcode_is_preserved(self) -> None:
        master, barcode = self._valid_rows()
        master.update(primary_barcode="036000291452", barcode_type="upc")
        barcode.update(barcode="036000291452", barcode_type="upc")
        report = self._report([master], [barcode])
        self.assertTrue(report["valid"])
        self.assertEqual(report["normalized_preview"]["masters"][0]["barcode_normalized"], "036000291452")

    def test_05_scientific_notation_barcode_is_rejected(self) -> None:
        master, barcode = self._valid_rows()
        master["primary_barcode"] = "4.006381E+12"
        barcode["barcode"] = "4.006381E+12"
        report = self._report([master], [barcode])
        self.assertIn("scientific_notation_barcode", self._codes(report))

    def test_06_ean8_checksum(self) -> None:
        self.assertIsNone(tool.validate_barcode_shape("96385074", "ean8"))

    def test_07_upc_checksum(self) -> None:
        self.assertIsNone(tool.validate_barcode_shape("036000291452", "upc"))

    def test_08_ean13_checksum(self) -> None:
        self.assertIsNone(tool.validate_barcode_shape("4006381333931", "ean13"))

    def test_09_gtin14_checksum(self) -> None:
        self.assertIsNone(tool.validate_barcode_shape("10012345000017", "gtin"))

    def test_10_invalid_checksum_is_rejected(self) -> None:
        master, barcode = self._valid_rows()
        master.update(primary_barcode="4006381333932")
        barcode.update(barcode="4006381333932")
        report = self._report([master], [barcode])
        self.assertIn("invalid_barcode", self._codes(report))

    def test_11_duplicate_barcode_for_same_master_warns(self) -> None:
        master, barcode = self._valid_rows()
        duplicate = deepcopy(barcode)
        duplicate.update(barcode_id="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2", is_primary="false")
        report = self._report([master], [barcode, duplicate])
        self.assertTrue(report["valid"])
        self.assertIn("duplicate_barcode_same_master", self._codes(report, "warnings"))

    def test_12_barcode_conflict_across_masters_blocks(self) -> None:
        first_master, first_barcode = self._valid_rows()
        second_master = deepcopy(first_master)
        second_master.update(
            master_product_id="22222222-2222-4222-8222-222222222222",
            name="Producto diferente",
        )
        second_barcode = deepcopy(first_barcode)
        second_barcode.update(
            barcode_id="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            master_product_id=second_master["master_product_id"],
        )
        report = self._report([first_master, second_master], [first_barcode, second_barcode])
        self.assertIn("barcode_conflict_across_masters", self._codes(report))
        self.assertEqual(len(report["barcode_conflicts"]), 1)

    def test_13_exact_semantic_duplicate_is_review_blocking(self) -> None:
        first_master, first_barcode = self._valid_rows()
        second_master = deepcopy(first_master)
        second_master.update(
            master_product_id="22222222-2222-4222-8222-222222222222",
            primary_barcode="96385074",
            barcode_type="ean8",
        )
        second_barcode = deepcopy(first_barcode)
        second_barcode.update(
            barcode_id="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            master_product_id=second_master["master_product_id"],
            barcode="96385074",
            barcode_type="ean8",
        )
        report = self._report([first_master, second_master], [first_barcode, second_barcode])
        self.assertIn("exact_semantic_duplicate", self._codes(report))
        self.assertEqual(report["semantic_duplicate_candidates"][0]["classification"], "exact")

    def test_14_missing_required_field_blocks(self) -> None:
        master, barcode = self._valid_rows()
        master["name"] = ""
        report = self._report([master], [barcode])
        self.assertIn("missing_required_field", self._codes(report))

    def test_15_package_size_and_unit_must_be_paired(self) -> None:
        master, barcode = self._valid_rows()
        master["package_unit"] = ""
        report = self._report([master], [barcode])
        self.assertIn("invalid_package_pair", self._codes(report))

    def test_16_confidence_uses_exact_decimal_and_range(self) -> None:
        master, barcode = self._valid_rows()
        master["confidence_score"] = "0.333300"
        barcode["confidence_score"] = "0.333300"
        valid = self._report([master], [barcode])
        self.assertEqual(valid["normalized_preview"]["masters"][0]["confidence_score"], "0.3333")
        master["confidence_score"] = "1.01"
        invalid = self._report([master], [barcode])
        self.assertIn("invalid_decimal", self._codes(invalid))

    def test_17_controlled_vocabulary_blocks_unknown_value(self) -> None:
        master, barcode = self._valid_rows()
        master["category_name"] = "Categoría inventada"
        report = self._report([master], [barcode])
        self.assertIn("invalid_vocabulary_value", self._codes(report))

    def test_18_unicode_is_nfc_normalized(self) -> None:
        master, barcode = self._valid_rows()
        master["name"] = "Cafe\u0301 de prueba"
        report = self._report([master], [barcode])
        self.assertEqual(report["normalized_preview"]["masters"][0]["name"], "Café de prueba")

    def test_19_internal_whitespace_is_collapsed(self) -> None:
        master, barcode = self._valid_rows()
        master["name"] = "  Café\t  de   prueba  "
        report = self._report([master], [barcode])
        self.assertEqual(report["normalized_preview"]["masters"][0]["name"], "Café de prueba")

    def test_20_image_requires_license(self) -> None:
        master, barcode = self._valid_rows()
        master["image_source_key"] = "images/fixture.png"
        report = self._report([master], [barcode])
        self.assertIn("image_license_required", self._codes(report))

    def test_21_record_hash_is_deterministic_and_uses_normalized_barcode(self) -> None:
        master, barcode = self._valid_rows()
        first = self._report([master], [barcode])
        master["primary_barcode"] = "4006 3813-33931"
        barcode["barcode"] = "4006 3813-33931"
        second = self._report([master], [barcode])
        self.assertEqual(first["record_hashes"], second["record_hashes"])

    def test_22_json_dry_run_is_deterministic(self) -> None:
        master, barcode = self._valid_rows()
        first = tool.report_json(self._report([master], [barcode]))
        second = tool.report_json(self._report([master], [barcode]))
        self.assertEqual(first, second)

    def test_23_validation_performs_zero_database_access(self) -> None:
        master, barcode = self._valid_rows()
        with mock.patch.object(socket, "socket", side_effect=AssertionError("network access attempted")):
            report = self._report([master], [barcode])
        self.assertFalse(report["database_access"])

    def test_24_invalid_uuid_blocks(self) -> None:
        master, barcode = self._valid_rows()
        master["master_product_id"] = "not-a-uuid"
        barcode["master_product_id"] = "not-a-uuid"
        report = self._report([master], [barcode])
        self.assertIn("invalid_uuid", self._codes(report))

    def test_25_attribution_is_required_for_cc_by(self) -> None:
        master, barcode = self._valid_rows()
        master.update(image_source_key="images/fixture.png", image_license="cc_by")
        report = self._report([master], [barcode])
        self.assertIn("image_attribution_required", self._codes(report))

    def test_26_prohibited_operational_column_blocks(self) -> None:
        master, barcode = self._valid_rows()
        master["stock"] = "10"
        report = self._report([master], [barcode], master_headers=tool.MASTER_HEADERS + ["stock"])
        self.assertIn("prohibited_column", self._codes(report))

    def test_27_internal_and_local_sku_are_not_global_types(self) -> None:
        self.assertIsNotNone(tool.validate_barcode_shape("ABC123", "internal"))
        self.assertIsNotNone(tool.validate_barcode_shape("ABC123", "local_sku"))

    def test_28_alternate_barcode_requires_review_but_does_not_block(self) -> None:
        master, primary = self._valid_rows()
        alternate = deepcopy(CASES["valid_alternate_barcode"])
        alternate.update(
            barcode_id="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2",
            master_product_id=master["master_product_id"],
            source="manufacturer",
            confidence_score="0.9",
            source_reference="fixture:p1.2:alternate",
        )
        report = self._report([master], [primary, alternate])
        self.assertTrue(report["valid"])
        self.assertIn("alternate_barcode_review_required", self._codes(report, "warnings"))

    def test_29_obvious_api_secret_in_known_field_blocks(self) -> None:
        master, barcode = self._valid_rows()
        master["description"] = "sb_secret_1234567890abcdefghijkl"
        report = self._report([master], [barcode])
        self.assertIn("prohibited_secret_value", self._codes(report))

    def test_30_canonical_uuid_v7_is_accepted(self) -> None:
        self.assertTrue(tool.is_valid_uuid("019f7193-f32a-777c-bcc0-c141bea60fb3"))

    def test_31_sync_empty_barcode_csv_creates_primary_row(self) -> None:
        master, _ = self._valid_rows()
        report, _, barcodes_path = self._sync([master], [])
        with barcodes_path.open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual(report["status"], "applied")
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["master_product_id"], master["master_product_id"])
        self.assertEqual(rows[0]["is_primary"], "true")
        backup_path = Path(str(report["backup_path"]))
        self.assertTrue(backup_path.is_file())
        self.assertEqual(
            backup_path.read_text(encoding="utf-8"),
            ",".join(tool.BARCODE_HEADERS) + "\n",
        )

    def test_32_sync_never_changes_master_seed_bytes(self) -> None:
        master, _ = self._valid_rows()
        _, masters_path, _ = self._sync([master], [])
        before = masters_path.read_bytes()
        tool.sync_primary_barcodes(
            masters_path=masters_path,
            barcodes_path=self.root / "master_catalog_barcodes.csv",
            backup_dir=self.root / "backups",
        )
        self.assertEqual(masters_path.read_bytes(), before)

    def test_33_sync_generates_valid_barcode_id(self) -> None:
        master, _ = self._valid_rows()
        _, _, barcodes_path = self._sync([master], [])
        with barcodes_path.open(encoding="utf-8", newline="") as handle:
            row = next(csv.DictReader(handle))
        self.assertTrue(tool.is_valid_uuid(row["barcode_id"]))

    def test_34_sync_rerun_is_byte_stable_no_op(self) -> None:
        master, _ = self._valid_rows()
        first, masters_path, barcodes_path = self._sync([master], [])
        first_bytes = barcodes_path.read_bytes()
        second = tool.sync_primary_barcodes(
            masters_path=masters_path,
            barcodes_path=barcodes_path,
            backup_dir=self.root / "backups",
        )
        self.assertEqual(first["would_insert"], 1)
        self.assertEqual(second["status"], "no_op")
        self.assertEqual(second["would_insert"], 0)
        self.assertEqual(second["would_promote"], 0)
        self.assertEqual(barcodes_path.read_bytes(), first_bytes)

    def test_35_sync_preserves_existing_barcode_id(self) -> None:
        master, barcode = self._valid_rows()
        report, _, barcodes_path = self._sync([master], [barcode])
        with barcodes_path.open(encoding="utf-8", newline="") as handle:
            row = next(csv.DictReader(handle))
        self.assertEqual(report["status"], "no_op")
        self.assertEqual(row["barcode_id"], barcode["barcode_id"])

    def test_36_sync_correct_existing_row_is_no_op(self) -> None:
        master, barcode = self._valid_rows()
        report, _, _ = self._sync([master], [barcode])
        self.assertEqual(report["already_correct"], 1)
        self.assertFalse(report["wrote_barcodes_csv"])

    def test_37_sync_cross_master_collision_writes_nothing(self) -> None:
        first_master, first_barcode = self._valid_rows()
        second_master = deepcopy(first_master)
        second_master.update(
            master_product_id="22222222-2222-4222-8222-222222222222",
            primary_barcode="96385074",
            barcode_type="ean8",
            name="Segundo producto",
        )
        first_barcode["master_product_id"] = second_master["master_product_id"]
        _, masters_path, barcodes_path = self._sync([first_master, second_master], [first_barcode], dry_run=True)
        before = barcodes_path.read_bytes()
        report = tool.sync_primary_barcodes(
            masters_path=masters_path,
            barcodes_path=barcodes_path,
            backup_dir=self.root / "backups",
        )
        self.assertGreater(report["cross_master_collisions"], 0)
        self.assertFalse(report["wrote_barcodes_csv"])
        self.assertEqual(barcodes_path.read_bytes(), before)

    def test_38_sync_contradictory_primary_writes_nothing(self) -> None:
        master, barcode = self._valid_rows()
        barcode.update(barcode="96385074", barcode_type="ean8")
        report, _, barcodes_path = self._sync([master], [barcode])
        self.assertEqual(report["contradictory_primary"], 1)
        self.assertFalse(report["wrote_barcodes_csv"])
        self.assertIn("96385074", barcodes_path.read_text(encoding="utf-8"))

    def test_39_sync_multiple_primary_fails_closed(self) -> None:
        master, first = self._valid_rows()
        second = deepcopy(first)
        second.update(
            barcode_id="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2",
            barcode="96385074",
            barcode_type="ean8",
        )
        report, _, _ = self._sync([master], [first, second])
        self.assertEqual(report["multiple_primary"], 1)
        self.assertFalse(report["can_apply"])

    def test_40_sync_preserves_leading_zero_barcode(self) -> None:
        master, _ = self._valid_rows()
        master.update(primary_barcode="036000291452", barcode_type="upc")
        _, _, barcodes_path = self._sync([master], [])
        with barcodes_path.open(encoding="utf-8", newline="") as handle:
            row = next(csv.DictReader(handle))
        self.assertEqual(row["barcode"], "036000291452")

    def test_41_sync_copies_seed_provenance(self) -> None:
        master, _ = self._valid_rows()
        master.update(source="manufacturer", confidence_score="0.91", source_reference="fixture:source:41")
        _, _, barcodes_path = self._sync([master], [])
        with barcodes_path.open(encoding="utf-8", newline="") as handle:
            row = next(csv.DictReader(handle))
        self.assertEqual(row["source"], "manufacturer")
        self.assertEqual(row["confidence_score"], "0.91")
        self.assertEqual(row["source_reference"], "fixture:source:41")

    def test_42_sync_atomic_replace_failure_preserves_original(self) -> None:
        master, _ = self._valid_rows()
        masters_path = self.root / "master_catalog_seed.csv"
        barcodes_path = self.root / "master_catalog_barcodes.csv"
        self._write_csv(masters_path, tool.MASTER_HEADERS, [master])
        self._write_csv(barcodes_path, tool.BARCODE_HEADERS, [])
        before = barcodes_path.read_bytes()
        with mock.patch.object(tool.os, "replace", side_effect=OSError("replace failed")):
            with self.assertRaises(OSError):
                tool.sync_primary_barcodes(
                    masters_path=masters_path,
                    barcodes_path=barcodes_path,
                    backup_dir=self.root / "backups",
                )
        self.assertEqual(barcodes_path.read_bytes(), before)

    def test_43_sync_dry_run_performs_zero_writes(self) -> None:
        master, _ = self._valid_rows()
        report, _, barcodes_path = self._sync([master], [], dry_run=True)
        before = barcodes_path.read_bytes()
        self.assertEqual(report["status"], "dry_run")
        self.assertFalse(report["wrote_barcodes_csv"])
        self.assertEqual(barcodes_path.read_bytes(), before)
        self.assertFalse((self.root / "backups").exists())

    def test_44_sync_handles_more_than_1500_rows_reasonably(self) -> None:
        template, _ = self._valid_rows()
        masters: list[dict[str, str]] = []
        for index in range(1501):
            master = deepcopy(template)
            master.update(
                master_product_id=str(uuid.uuid5(uuid.NAMESPACE_URL, f"catalog-master-{index}")),
                primary_barcode=self._ean13(index),
                name=f"Producto sintético {index}",
            )
            masters.append(master)
        started = time.monotonic()
        report, _, _ = self._sync(masters, [], dry_run=True)
        elapsed = time.monotonic() - started
        self.assertTrue(report["can_apply"])
        self.assertEqual(report["would_insert"], 1501)
        self.assertLess(elapsed, 5.0)

    def test_45_sync_promotes_unambiguous_alias_preserving_provenance(self) -> None:
        master, alias = self._valid_rows()
        alias.update(is_primary="false", source="supplier", confidence_score="0.87", source_reference="fixture:alias")
        report, _, barcodes_path = self._sync([master], [alias])
        with barcodes_path.open(encoding="utf-8", newline="") as handle:
            row = next(csv.DictReader(handle))
        self.assertEqual(report["would_promote"], 1)
        self.assertEqual(row["is_primary"], "true")
        self.assertEqual(row["barcode_id"], alias["barcode_id"])
        self.assertEqual(row["source_reference"], "fixture:alias")

    def test_46_sync_ambiguous_aliases_fail_closed(self) -> None:
        master, first = self._valid_rows()
        first["is_primary"] = "false"
        second = deepcopy(first)
        second["barcode_id"] = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2"
        report, _, _ = self._sync([master], [first, second])
        self.assertEqual(report["ambiguous_alias"], 1)
        self.assertFalse(report["can_apply"])

    def test_47_sync_skips_invalid_master_and_materializes_valid_master(self) -> None:
        valid, _ = self._valid_rows()
        invalid = deepcopy(valid)
        invalid.update(
            master_product_id="22222222-2222-4222-8222-222222222222",
            primary_barcode="123",
            name="Master inválido aislado",
        )
        report, _, barcodes_path = self._sync([valid, invalid], [])
        with barcodes_path.open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual(report["status"], "applied")
        self.assertEqual(report["masters_valid"], 1)
        self.assertEqual(report["masters_skipped_invalid"], 1)
        self.assertEqual(report["input_error_count"], 1)
        self.assertEqual(report["blocking_input_error_count"], 0)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["master_product_id"], valid["master_product_id"])

    def test_48_prune_removes_only_invalid_barcode_master_and_audits_full_row(self) -> None:
        valid, barcode = self._valid_rows()
        invalid = deepcopy(valid)
        invalid.update(
            master_product_id="22222222-2222-4222-8222-222222222222",
            primary_barcode="123",
            name="Master inválido aislado",
        )
        report, masters_path, _, rejected_path = self._prune([valid, invalid], [barcode])
        with masters_path.open(encoding="utf-8", newline="") as handle:
            remaining = list(csv.DictReader(handle))
        with rejected_path.open(encoding="utf-8", newline="") as handle:
            rejected = list(csv.DictReader(handle))
        self.assertEqual(report["status"], "applied")
        self.assertEqual(remaining, [valid])
        self.assertEqual(len(rejected), 1)
        self.assertEqual(
            {key: rejected[0][key] for key in tool.MASTER_HEADERS},
            invalid,
        )
        self.assertEqual(rejected[0]["rejection_reason"], "invalid_primary_barcode")

    def test_49_prune_never_changes_relational_barcode_csv(self) -> None:
        valid, barcode = self._valid_rows()
        invalid = deepcopy(valid)
        invalid.update(
            master_product_id="22222222-2222-4222-8222-222222222222",
            primary_barcode="123",
        )
        _, _, barcodes_path, _ = self._prune([valid, invalid], [barcode])
        before = barcodes_path.read_bytes()
        tool.prune_invalid_barcode_masters(
            masters_path=self.root / "master_catalog_seed.csv",
            barcodes_path=barcodes_path,
            rejected_report_path=self.root / "reports" / "rejected_invalid_barcode_rows.csv",
            backup_dir=self.root / "backups",
            expected_count=1,
        )
        self.assertEqual(barcodes_path.read_bytes(), before)

    def test_50_prune_aborts_if_target_has_relational_barcode(self) -> None:
        invalid, relation = self._valid_rows()
        invalid.update(primary_barcode="123")
        relation.update(barcode="123", barcode_type="ean13")
        report, masters_path, _, rejected_path = self._prune([invalid], [relation])
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(report["related_barcode_rows"], 1)
        with masters_path.open(encoding="utf-8", newline="") as handle:
            self.assertEqual(len(list(csv.DictReader(handle))), 1)
        self.assertFalse(rejected_path.exists())

    def test_51_prune_creates_external_seed_backup(self) -> None:
        valid, barcode = self._valid_rows()
        invalid = deepcopy(valid)
        invalid.update(
            master_product_id="22222222-2222-4222-8222-222222222222",
            primary_barcode="123",
        )
        masters_path = self.root / "master_catalog_seed.csv"
        self._write_csv(masters_path, tool.MASTER_HEADERS, [valid, invalid])
        original = masters_path.read_bytes()
        self._write_csv(self.root / "master_catalog_barcodes.csv", tool.BARCODE_HEADERS, [barcode])
        report = tool.prune_invalid_barcode_masters(
            masters_path=masters_path,
            barcodes_path=self.root / "master_catalog_barcodes.csv",
            rejected_report_path=self.root / "reports" / "rejected_invalid_barcode_rows.csv",
            backup_dir=self.root / "backups",
            expected_count=1,
        )
        backup = Path(str(report["backup_path"]))
        self.assertTrue(backup.is_file())
        self.assertEqual(backup.read_bytes(), original)

    def test_52_prune_replace_failure_preserves_seed(self) -> None:
        valid, barcode = self._valid_rows()
        invalid = deepcopy(valid)
        invalid.update(
            master_product_id="22222222-2222-4222-8222-222222222222",
            primary_barcode="123",
        )
        masters_path = self.root / "master_catalog_seed.csv"
        barcodes_path = self.root / "master_catalog_barcodes.csv"
        rejected_path = self.root / "reports" / "rejected_invalid_barcode_rows.csv"
        self._write_csv(masters_path, tool.MASTER_HEADERS, [valid, invalid])
        self._write_csv(barcodes_path, tool.BARCODE_HEADERS, [barcode])
        original = masters_path.read_bytes()
        with mock.patch.object(tool.os, "replace", side_effect=OSError("replace failed")):
            with self.assertRaises(OSError):
                tool.prune_invalid_barcode_masters(
                    masters_path=masters_path,
                    barcodes_path=barcodes_path,
                    rejected_report_path=rejected_path,
                    backup_dir=self.root / "backups",
                    expected_count=1,
                )
        self.assertEqual(masters_path.read_bytes(), original)
        self.assertFalse(rejected_path.exists())

    def test_53_prune_rerun_is_byte_stable_no_op(self) -> None:
        valid, barcode = self._valid_rows()
        invalid = deepcopy(valid)
        invalid.update(
            master_product_id="22222222-2222-4222-8222-222222222222",
            primary_barcode="123",
        )
        _, masters_path, barcodes_path, rejected_path = self._prune([valid, invalid], [barcode])
        seed_bytes = masters_path.read_bytes()
        rejected_bytes = rejected_path.read_bytes()
        second = tool.prune_invalid_barcode_masters(
            masters_path=masters_path,
            barcodes_path=barcodes_path,
            rejected_report_path=rejected_path,
            backup_dir=self.root / "backups",
            expected_count=1,
        )
        self.assertEqual(second["status"], "no_op")
        self.assertEqual(masters_path.read_bytes(), seed_bytes)
        self.assertEqual(rejected_path.read_bytes(), rejected_bytes)

    def test_54_prune_dry_run_performs_zero_writes(self) -> None:
        valid, barcode = self._valid_rows()
        invalid = deepcopy(valid)
        invalid.update(
            master_product_id="22222222-2222-4222-8222-222222222222",
            primary_barcode="123",
        )
        report, masters_path, barcodes_path, rejected_path = self._prune(
            [valid, invalid], [barcode], dry_run=True
        )
        seed_bytes = masters_path.read_bytes()
        barcode_bytes = barcodes_path.read_bytes()
        self.assertEqual(report["status"], "dry_run")
        self.assertEqual(masters_path.read_bytes(), seed_bytes)
        self.assertEqual(barcodes_path.read_bytes(), barcode_bytes)
        self.assertFalse(rejected_path.exists())
        self.assertFalse((self.root / "backups").exists())

    def test_55_exact_prune_removes_every_group_member_without_survivor(self) -> None:
        masters, barcodes = self._exact_duplicate_fixture()
        report, masters_path, _, _, _ = self._exact_prune(masters, barcodes)
        with masters_path.open(encoding="utf-8", newline="") as handle:
            remaining = list(csv.DictReader(handle))
        self.assertEqual(report["status"], "applied")
        self.assertEqual(report["exact_group_count"], 1)
        self.assertEqual(report["exact_master_count"], 2)
        self.assertEqual(remaining, [masters[2]])

    def test_56_exact_prune_removes_target_barcodes_and_preserves_retained_rows(self) -> None:
        masters, barcodes = self._exact_duplicate_fixture()
        _, masters_path, barcodes_path, _, _ = self._exact_prune(masters, barcodes)
        with masters_path.open(encoding="utf-8", newline="") as handle:
            remaining_masters = list(csv.DictReader(handle))
        with barcodes_path.open(encoding="utf-8", newline="") as handle:
            remaining_barcodes = list(csv.DictReader(handle))
        self.assertEqual(remaining_masters, [masters[2]])
        self.assertEqual(remaining_barcodes, [barcodes[2]])
        self.assertEqual(remaining_masters[0]["master_product_id"], masters[2]["master_product_id"])
        self.assertEqual(remaining_barcodes[0]["barcode_id"], barcodes[2]["barcode_id"])

    def test_57_exact_prune_reports_preserve_rows_and_stable_group_id(self) -> None:
        masters, barcodes = self._exact_duplicate_fixture()
        _, _, _, rejected_masters, rejected_barcodes = self._exact_prune(masters, barcodes)
        with rejected_masters.open(encoding="utf-8", newline="") as handle:
            master_rows = list(csv.DictReader(handle))
        with rejected_barcodes.open(encoding="utf-8", newline="") as handle:
            barcode_rows = list(csv.DictReader(handle))
        self.assertEqual(
            [{key: row[key] for key in tool.MASTER_HEADERS} for row in master_rows],
            masters[:2],
        )
        self.assertEqual(
            [{key: row[key] for key in tool.BARCODE_HEADERS} for row in barcode_rows],
            barcodes[:2],
        )
        self.assertEqual({row["rejection_reason"] for row in master_rows}, {"exact_semantic_duplicate"})
        self.assertEqual(
            {row["duplicate_group_id"] for row in master_rows},
            {row["duplicate_group_id"] for row in barcode_rows},
        )
        self.assertEqual(len(master_rows[0]["duplicate_group_id"]), 64)

    def test_58_exact_prune_aborts_when_target_relation_is_missing(self) -> None:
        masters, barcodes = self._exact_duplicate_fixture()
        original_masters = deepcopy(masters)
        report, masters_path, barcodes_path, rejected_masters, rejected_barcodes = (
            self._exact_prune(masters, [barcodes[0], barcodes[2]])
        )
        with masters_path.open(encoding="utf-8", newline="") as handle:
            current_masters = list(csv.DictReader(handle))
        with barcodes_path.open(encoding="utf-8", newline="") as handle:
            current_barcodes = list(csv.DictReader(handle))
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(current_masters, original_masters)
        self.assertEqual(len(current_barcodes), 2)
        self.assertFalse(rejected_masters.exists())
        self.assertFalse(rejected_barcodes.exists())

    def test_59_exact_prune_aborts_on_multiple_target_primaries(self) -> None:
        masters, barcodes = self._exact_duplicate_fixture()
        extra = deepcopy(barcodes[0])
        extra.update(
            barcode_id="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4",
            barcode="036000291452",
            barcode_type="upc",
        )
        report, _, _, _, _ = self._exact_prune(masters, [*barcodes, extra])
        self.assertEqual(report["status"], "blocked")
        self.assertTrue(
            any(blocker["code"] == "target_primary_relation_count" for blocker in report["blockers"])
        )

    def test_60_exact_prune_backs_up_both_active_datasets(self) -> None:
        masters, barcodes = self._exact_duplicate_fixture()
        masters_path = self.root / "master_catalog_seed.csv"
        barcodes_path = self.root / "master_catalog_barcodes.csv"
        self._write_csv(masters_path, tool.MASTER_HEADERS, masters)
        self._write_csv(barcodes_path, tool.BARCODE_HEADERS, barcodes)
        master_bytes = masters_path.read_bytes()
        barcode_bytes = barcodes_path.read_bytes()
        report = tool.prune_exact_semantic_duplicates(
            masters_path=masters_path,
            barcodes_path=barcodes_path,
            rejected_masters_path=self.root / "reports" / "masters.csv",
            rejected_barcodes_path=self.root / "reports" / "barcodes.csv",
            backup_dir=self.root / "backups",
            expected_group_count=1,
            expected_master_count=2,
            expected_barcode_count=2,
        )
        self.assertEqual(Path(str(report["seed_backup_path"])).read_bytes(), master_bytes)
        self.assertEqual(Path(str(report["barcode_backup_path"])).read_bytes(), barcode_bytes)

    def test_61_exact_prune_rolls_back_first_dataset_if_second_replace_fails(self) -> None:
        masters, barcodes = self._exact_duplicate_fixture()
        masters_path = self.root / "master_catalog_seed.csv"
        barcodes_path = self.root / "master_catalog_barcodes.csv"
        rejected_masters = self.root / "reports" / "masters.csv"
        rejected_barcodes = self.root / "reports" / "barcodes.csv"
        self._write_csv(masters_path, tool.MASTER_HEADERS, masters)
        self._write_csv(barcodes_path, tool.BARCODE_HEADERS, barcodes)
        master_bytes = masters_path.read_bytes()
        barcode_bytes = barcodes_path.read_bytes()
        real_replace = tool.os.replace

        def fail_seed_replace(source: object, destination: object) -> None:
            if Path(destination) == masters_path:
                raise OSError("seed replace failed")
            real_replace(source, destination)

        with mock.patch.object(tool.os, "replace", side_effect=fail_seed_replace):
            with self.assertRaises(OSError):
                tool.prune_exact_semantic_duplicates(
                    masters_path=masters_path,
                    barcodes_path=barcodes_path,
                    rejected_masters_path=rejected_masters,
                    rejected_barcodes_path=rejected_barcodes,
                    backup_dir=self.root / "backups",
                    expected_group_count=1,
                    expected_master_count=2,
                    expected_barcode_count=2,
                )
        self.assertEqual(masters_path.read_bytes(), master_bytes)
        self.assertEqual(barcodes_path.read_bytes(), barcode_bytes)

    def test_62_exact_prune_rerun_is_no_op_and_byte_stable(self) -> None:
        masters, barcodes = self._exact_duplicate_fixture()
        _, masters_path, barcodes_path, rejected_masters, rejected_barcodes = self._exact_prune(
            masters, barcodes
        )
        hashes_before = [
            path.read_bytes()
            for path in (masters_path, barcodes_path, rejected_masters, rejected_barcodes)
        ]
        second = tool.prune_exact_semantic_duplicates(
            masters_path=masters_path,
            barcodes_path=barcodes_path,
            rejected_masters_path=rejected_masters,
            rejected_barcodes_path=rejected_barcodes,
            backup_dir=self.root / "backups",
            expected_group_count=1,
            expected_master_count=2,
            expected_barcode_count=2,
        )
        self.assertEqual(second["status"], "no_op")
        self.assertEqual(
            [
                path.read_bytes()
                for path in (masters_path, barcodes_path, rejected_masters, rejected_barcodes)
            ],
            hashes_before,
        )

    def test_63_exact_prune_dry_run_performs_zero_writes(self) -> None:
        masters, barcodes = self._exact_duplicate_fixture()
        report, masters_path, barcodes_path, rejected_masters, rejected_barcodes = (
            self._exact_prune(masters, barcodes, dry_run=True)
        )
        with masters_path.open(encoding="utf-8", newline="") as handle:
            current_masters = list(csv.DictReader(handle))
        with barcodes_path.open(encoding="utf-8", newline="") as handle:
            current_barcodes = list(csv.DictReader(handle))
        self.assertEqual(report["status"], "dry_run")
        self.assertEqual(len(current_masters), 3)
        self.assertEqual(len(current_barcodes), 3)
        self.assertFalse(rejected_masters.exists())
        self.assertFalse(rejected_barcodes.exists())
        self.assertFalse((self.root / "backups").exists())

    def test_64_preflight_prune_preserves_only_insert_rows_and_audits_targets(self) -> None:
        masters, barcodes, plan, snapshot = self._preflight_fixture()
        report, masters_path, barcodes_path, reports = self._preflight_prune(
            masters, barcodes, plan, snapshot
        )
        with masters_path.open(encoding="utf-8", newline="") as handle:
            remaining_masters = list(csv.DictReader(handle))
        with barcodes_path.open(encoding="utf-8", newline="") as handle:
            remaining_barcodes = list(csv.DictReader(handle))
        self.assertEqual(report["status"], "applied")
        self.assertEqual(report["target_master_count"], 2)
        self.assertEqual(remaining_masters, [masters[2]])
        self.assertEqual(remaining_barcodes, [barcodes[2]])
        self.assertEqual(remaining_masters[0]["master_product_id"], masters[2]["master_product_id"])
        self.assertEqual(remaining_barcodes[0]["barcode_id"], barcodes[2]["barcode_id"])
        self.assertTrue(all(path.is_file() for path in reports))
        with reports[0].open(encoding="utf-8", newline="") as handle:
            review_master = next(csv.DictReader(handle))
        with reports[2].open(encoding="utf-8", newline="") as handle:
            conflict_master = next(csv.DictReader(handle))
        self.assertEqual(review_master["rejection_reason"], "near_semantic_duplicate_review")
        self.assertEqual(conflict_master["hosted_owner_master_id"], "55555555-5555-4555-8555-555555555555")
        self.assertEqual(conflict_master["hosted_barcode_id"], "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")

    def test_65_preflight_prune_aborts_on_target_relation_inconsistency(self) -> None:
        masters, barcodes, plan, snapshot = self._preflight_fixture()
        original_masters = deepcopy(masters)
        original_barcodes = [barcodes[0], barcodes[2]]
        report, masters_path, barcodes_path, reports = self._preflight_prune(
            masters, original_barcodes, plan, snapshot
        )
        with masters_path.open(encoding="utf-8", newline="") as handle:
            current_masters = list(csv.DictReader(handle))
        with barcodes_path.open(encoding="utf-8", newline="") as handle:
            current_barcodes = list(csv.DictReader(handle))
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(current_masters, original_masters)
        self.assertEqual(current_barcodes, original_barcodes)
        self.assertFalse(any(path.exists() for path in reports))
        self.assertFalse((self.root / "backups").exists())

    def test_66_preflight_prune_creates_pair_backups_and_reruns_byte_stable_no_op(self) -> None:
        masters, barcodes, plan, snapshot = self._preflight_fixture()
        first, masters_path, barcodes_path, reports = self._preflight_prune(
            masters, barcodes, plan, snapshot
        )
        self.assertEqual(Path(str(first["seed_backup_path"])).read_bytes(), self._csv_bytes(tool.MASTER_HEADERS, masters))
        self.assertEqual(
            Path(str(first["barcode_backup_path"])).read_bytes(),
            self._csv_bytes(tool.BARCODE_HEADERS, barcodes),
        )
        before = [path.read_bytes() for path in (masters_path, barcodes_path, *reports)]
        second = tool.prune_preflight_blockers(
            masters_path=masters_path,
            barcodes_path=barcodes_path,
            plan_path=self.root / "plan.json",
            snapshot_path=self.root / "snapshot.json",
            rejected_review_masters_path=reports[0],
            rejected_review_barcodes_path=reports[1],
            rejected_conflict_masters_path=reports[2],
            rejected_conflict_barcodes_path=reports[3],
            backup_dir=self.root / "backups",
            expected_review_count=1,
            expected_conflict_count=1,
        )
        self.assertEqual(second["status"], "no_op")
        self.assertEqual([path.read_bytes() for path in (masters_path, barcodes_path, *reports)], before)

    def test_67_preflight_prune_rolls_back_pair_if_second_replace_fails(self) -> None:
        masters, barcodes, plan, snapshot = self._preflight_fixture()
        masters_path = self.root / "master_catalog_seed.csv"
        barcodes_path = self.root / "master_catalog_barcodes.csv"
        self._write_csv(masters_path, tool.MASTER_HEADERS, masters)
        self._write_csv(barcodes_path, tool.BARCODE_HEADERS, barcodes)
        original_master_bytes = masters_path.read_bytes()
        original_barcode_bytes = barcodes_path.read_bytes()
        real_replace = tool.os.replace

        def fail_seed_replace(source: object, destination: object) -> None:
            if Path(destination) == masters_path:
                raise OSError("seed replace failed")
            real_replace(source, destination)

        with mock.patch.object(tool.os, "replace", side_effect=fail_seed_replace):
            with self.assertRaises(OSError):
                self._preflight_prune(masters, barcodes, plan, snapshot)
        self.assertEqual(masters_path.read_bytes(), original_master_bytes)
        self.assertEqual(barcodes_path.read_bytes(), original_barcode_bytes)
        self.assertFalse(any((self.root / "reports").glob("*.csv")))

    def test_68_preflight_prune_rejects_tampered_plan_hash_without_writes(self) -> None:
        masters, barcodes, plan, snapshot = self._preflight_fixture()
        plan["masters"]["reviews"][0]["reason"] = "tampered"  # type: ignore[index]
        report, masters_path, barcodes_path, reports = self._preflight_prune(
            masters, barcodes, plan, snapshot
        )
        self.assertEqual(report["status"], "blocked")
        self.assertTrue(any(item["code"] == "invalid_plan_hash" for item in report["blockers"]))
        self.assertEqual(masters_path.read_bytes(), self._csv_bytes(tool.MASTER_HEADERS, masters))
        self.assertEqual(barcodes_path.read_bytes(), self._csv_bytes(tool.BARCODE_HEADERS, barcodes))
        self.assertFalse(any(path.exists() for path in reports))

    def test_69_preflight_prune_rejects_snapshot_hash_mismatch_without_writes(self) -> None:
        masters, barcodes, plan, snapshot = self._preflight_fixture()
        snapshot["global_barcodes"][0]["id"] = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"  # type: ignore[index]
        report, masters_path, barcodes_path, reports = self._preflight_prune(
            masters, barcodes, plan, snapshot
        )
        self.assertEqual(report["status"], "blocked")
        self.assertTrue(
            any(item["code"] == "snapshot_hash_mismatch" for item in report["blockers"])
        )
        self.assertEqual(masters_path.read_bytes(), self._csv_bytes(tool.MASTER_HEADERS, masters))
        self.assertEqual(barcodes_path.read_bytes(), self._csv_bytes(tool.BARCODE_HEADERS, barcodes))
        self.assertFalse(any(path.exists() for path in reports))

    def test_70_preflight_prune_rejects_changed_survivor_payloads(self) -> None:
        for target, field, changed_value, blocker_code in (
            ("master", "name", "Payload modificado", "planner_insert_master_payload_mismatch"),
            (
                "barcode",
                "source_reference",
                "fixture:changed",
                "planner_insert_barcode_payload_mismatch",
            ),
        ):
            with self.subTest(target=target):
                masters, barcodes, plan, snapshot = self._preflight_fixture()
                rows = masters if target == "master" else barcodes
                rows[2][field] = changed_value
                report, masters_path, barcodes_path, reports = self._preflight_prune(
                    masters, barcodes, plan, snapshot
                )
                self.assertEqual(report["status"], "blocked")
                self.assertTrue(
                    any(item["code"] == blocker_code for item in report["blockers"])
                )
                self.assertEqual(
                    masters_path.read_bytes(), self._csv_bytes(tool.MASTER_HEADERS, masters)
                )
                self.assertEqual(
                    barcodes_path.read_bytes(), self._csv_bytes(tool.BARCODE_HEADERS, barcodes)
                )
                self.assertFalse(any(path.exists() for path in reports))

    def test_71_exact_prune_rejects_incomplete_multirelation_barcode_report(self) -> None:
        masters, barcodes = self._exact_duplicate_fixture()
        alternate = deepcopy(barcodes[0])
        alternate.update(
            barcode_id="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4",
            barcode="036000291452",
            barcode_type="upc",
            is_primary="false",
        )
        _, masters_path, barcodes_path, rejected_masters, rejected_barcodes = self._exact_prune(
            masters,
            [barcodes[0], alternate, barcodes[1], barcodes[2]],
            expected_barcode_count=3,
        )
        active_before = (masters_path.read_bytes(), barcodes_path.read_bytes())
        with rejected_barcodes.open(encoding="utf-8", newline="") as handle:
            rejected_rows = list(csv.DictReader(handle))
        self._write_csv(
            rejected_barcodes,
            tool.REJECTED_EXACT_BARCODE_HEADERS,
            [row for row in rejected_rows if row["barcode_id"] != alternate["barcode_id"]],
        )

        report = tool.prune_exact_semantic_duplicates(
            masters_path=masters_path,
            barcodes_path=barcodes_path,
            rejected_masters_path=rejected_masters,
            rejected_barcodes_path=rejected_barcodes,
            backup_dir=self.root / "backups",
            expected_group_count=1,
            expected_master_count=2,
            expected_barcode_count=3,
        )

        self.assertEqual(report["status"], "blocked")
        self.assertFalse(report["barcode_report_matches"])
        self.assertEqual((masters_path.read_bytes(), barcodes_path.read_bytes()), active_before)

    def test_72_preflight_prune_rolls_back_both_datasets_after_post_write_failure(self) -> None:
        masters, barcodes, plan, snapshot = self._preflight_fixture()
        masters_path = self.root / "master_catalog_seed.csv"
        barcodes_path = self.root / "master_catalog_barcodes.csv"
        original_master_bytes = self._csv_bytes(tool.MASTER_HEADERS, masters)
        original_barcode_bytes = self._csv_bytes(tool.BARCODE_HEADERS, barcodes)
        real_read_bytes = Path.read_bytes
        seed_reads = 0

        def fail_post_write_seed_read(path: Path) -> bytes:
            nonlocal seed_reads
            if path == masters_path:
                seed_reads += 1
                if seed_reads == 2:
                    raise OSError("post-write seed hash failed")
            return real_read_bytes(path)

        with mock.patch.object(
            Path, "read_bytes", autospec=True, side_effect=fail_post_write_seed_read
        ):
            with self.assertRaises(OSError):
                self._preflight_prune(masters, barcodes, plan, snapshot)

        self.assertEqual(masters_path.read_bytes(), original_master_bytes)
        self.assertEqual(barcodes_path.read_bytes(), original_barcode_bytes)
        self.assertFalse(any((self.root / "reports").glob("*.csv")))


if __name__ == "__main__":
    unittest.main()
