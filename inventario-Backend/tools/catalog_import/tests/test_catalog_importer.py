from __future__ import annotations

import json
import socket
import sys
import unittest
from copy import deepcopy
from pathlib import Path
from unittest import mock


TOOL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL_DIR))

import catalog_importer as importer  # noqa: E402
import catalog_tool  # noqa: E402


FIXTURES = Path(__file__).resolve().parent / "fixtures"
VALID = FIXTURES / "valid"
BATCH_ID = "33333333-3333-4333-8333-333333333333"


class CatalogImporterTest(unittest.TestCase):
    def _report(self) -> dict[str, object]:
        return catalog_tool.validate_dataset(
            masters_path=VALID / "master_catalog_seed.csv",
            barcodes_path=VALID / "master_catalog_barcodes.csv",
            manifest_path=catalog_tool.DEFAULT_MANIFEST,
            vocabularies_path=catalog_tool.DEFAULT_CONFIG,
        )

    @staticmethod
    def _empty_snapshot() -> dict[str, object]:
        return {"snapshot_version": 1, "masters": [], "global_barcodes": []}

    def _matching_snapshot(self) -> dict[str, object]:
        report = self._report()
        master = report["normalized_preview"]["masters"][0]
        remote_master = {
            "id": master["master_product_id"],
            "barcode": master["barcode_normalized"],
            "gtin": master["barcode_normalized"],
            "name": master["name"],
            "product_name": master["name"],
            "brand": master["brand"],
            "manufacturer": master["manufacturer"],
            "category_name": master["category_name"],
            "category": master["category_name"],
            "subcategory_name": master["subcategory_name"],
            "package_size": master["package_size"],
            "package_unit": master["package_unit"],
            "unit_type": master["unit_type"],
            "unit": master["unit_type"],
            "description": master["description"],
            "source": master["source"],
            "verification_status": master["verification_status"],
            "confidence_score": master["confidence_score"],
            "version": 7,
            "deleted_at": None,
            "metadata": {"catalog_import": {
                "record_hash": master["record_hash"],
                "source_reference": master["source_reference"],
            }},
        }
        remote_barcodes = []
        for index, barcode in enumerate(report["normalized_preview"]["barcodes"], start=3):
            remote_barcodes.append({
                "id": barcode["barcode_id"],
                "scope": "global",
                "business_id": None,
                "product_id": None,
                "master_product_id": barcode["master_product_id"],
                "barcode": barcode["barcode_normalized"],
                "barcode_normalized": barcode["barcode_normalized"],
                "barcode_type": barcode["barcode_type"],
                "is_primary": barcode["is_primary"],
                "status": "active",
                "source": barcode["source"],
                "confidence_score": barcode["confidence_score"],
                "version": index,
                "deleted_at": None,
                "metadata": {"catalog_import": {
                    "record_hash": barcode["record_hash"],
                    "source_reference": barcode["source_reference"],
                }},
            })
        return {"snapshot_version": 1, "masters": [remote_master], "global_barcodes": remote_barcodes}

    def _plan(self, snapshot: dict[str, object]) -> dict[str, object]:
        return importer.build_import_plan(
            validation_report=self._report(),
            snapshot=snapshot,
            import_batch_id=BATCH_ID,
        )

    def test_01_snapshot_parsing_is_sorted_and_strict(self) -> None:
        snapshot = importer.load_snapshot(FIXTURES / "existing_catalog_snapshot.json")
        self.assertEqual(snapshot, self._empty_snapshot())
        with self.assertRaises(importer.ImporterError):
            importer.parse_snapshot({"snapshot_version": 2, "masters": [], "global_barcodes": []})

    def test_02_plan_is_deterministic(self) -> None:
        first = self._plan(self._empty_snapshot())
        second = self._plan(self._empty_snapshot())
        self.assertEqual(importer.stable_json(first), importer.stable_json(second))
        self.assertEqual(first["plan_hash"], second["plan_hash"])

    def test_03_absent_entities_are_inserts(self) -> None:
        plan = self._plan(self._empty_snapshot())
        self.assertEqual(plan["summary"]["master_inserts"], 1)
        self.assertEqual(plan["summary"]["barcode_inserts"], 2)
        self.assertTrue(plan["ready_to_apply"])

    def test_04_matching_entities_are_no_ops(self) -> None:
        plan = self._plan(self._matching_snapshot())
        self.assertEqual(plan["summary"]["master_no_ops"], 1)
        self.assertEqual(plan["summary"]["barcode_no_ops"], 2)
        self.assertEqual(plan["masters"]["no_ops"][0]["expected_version"], 7)

    def test_05_allowed_master_change_is_update(self) -> None:
        snapshot = self._matching_snapshot()
        snapshot["masters"][0]["brand"] = "Marca anterior"
        snapshot["masters"][0]["metadata"] = {}
        plan = self._plan(snapshot)
        self.assertEqual(plan["summary"]["master_updates"], 1)
        self.assertEqual(plan["masters"]["updates"][0]["expected_version"], 7)

    def test_06_cross_master_barcode_is_conflict(self) -> None:
        snapshot = self._empty_snapshot()
        snapshot["global_barcodes"] = [{
            "id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1",
            "scope": "global",
            "master_product_id": "22222222-2222-4222-8222-222222222222",
            "barcode": "4006381333931",
            "is_primary": True,
            "status": "active",
            "version": 1,
            "deleted_at": None,
        }]
        plan = self._plan(snapshot)
        self.assertFalse(plan["ready_to_apply"])
        self.assertGreaterEqual(plan["summary"]["blocking_items"], 1)
        self.assertIn("another master", plan["masters"]["conflicts"][0]["reason"])

    def test_07_expected_versions_protect_stale_snapshot(self) -> None:
        plan = self._plan(self._matching_snapshot())
        payload = importer.plan_rpc_payload(plan)
        self.assertEqual(payload["p_masters"][0]["expected_version"], 7)
        self.assertEqual(
            sorted(row["expected_version"] for row in payload["p_barcodes"]),
            [3, 4],
        )

    def test_08_tombstoned_barcode_requires_review(self) -> None:
        snapshot = self._matching_snapshot()
        snapshot["global_barcodes"][0]["deleted_at"] = "2026-09-07T12:00:00Z"
        plan = self._plan(snapshot)
        self.assertFalse(plan["ready_to_apply"])
        self.assertGreater(plan["summary"]["barcode_reviews"], 0)

    def test_09_remote_semantic_candidate_requires_review(self) -> None:
        snapshot = self._matching_snapshot()
        snapshot["masters"][0]["id"] = "22222222-2222-4222-8222-222222222222"
        snapshot["global_barcodes"] = []
        plan = self._plan(snapshot)
        self.assertEqual(plan["summary"]["master_reviews"], 1)

    def test_10_plan_json_contains_required_contract(self) -> None:
        plan = self._plan(self._empty_snapshot())
        self.assertEqual(plan["plan_version"], 1)
        self.assertEqual(plan["dataset_version"], "0.1.0")
        self.assertEqual(plan["import_batch_id"], BATCH_ID)
        self.assertEqual(len(plan["snapshot_hash"]), 64)
        self.assertEqual(len(plan["plan_hash"]), 64)
        self.assertIn("record_hash", plan["masters"]["inserts"][0]["record"])

    def test_11_planning_has_zero_network_or_database_writes(self) -> None:
        masters_path = VALID / "master_catalog_seed.csv"
        barcodes_path = VALID / "master_catalog_barcodes.csv"
        before = (masters_path.read_bytes(), barcodes_path.read_bytes())
        with mock.patch.object(socket, "socket", side_effect=AssertionError("network access attempted")):
            self._plan(self._empty_snapshot())
        after = (masters_path.read_bytes(), barcodes_path.read_bytes())
        self.assertEqual(before, after)

    def test_12_tampered_plan_is_not_applyable(self) -> None:
        plan = self._plan(self._empty_snapshot())
        plan["dataset_version"] = "tampered"
        with self.assertRaises(importer.ImporterError):
            importer.plan_rpc_payload(plan)

    def test_13_post_import_verification_passes_matching_snapshot(self) -> None:
        plan = self._plan(self._empty_snapshot())
        report = importer.verify_import_plan(plan, self._matching_snapshot())
        self.assertTrue(report["valid"])
        self.assertEqual(report["verified_masters"], 1)
        self.assertEqual(report["verified_barcodes"], 2)

    def test_14_post_import_verification_detects_stale_payload(self) -> None:
        plan = self._plan(self._matching_snapshot())
        changed = deepcopy(self._matching_snapshot())
        changed["masters"][0]["metadata"] = {}
        changed["masters"][0]["brand"] = "Cambio concurrente"
        report = importer.verify_import_plan(plan, changed)
        self.assertFalse(report["valid"])
        self.assertEqual(report["errors"][0]["reason"], "canonical_payload_mismatch")


if __name__ == "__main__":
    unittest.main()
