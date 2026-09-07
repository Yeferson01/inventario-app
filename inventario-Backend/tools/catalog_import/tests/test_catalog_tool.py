from __future__ import annotations

import csv
import json
import socket
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path
from unittest import mock


TOOL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL_DIR))

import catalog_tool as tool  # noqa: E402


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


if __name__ == "__main__":
    unittest.main()
