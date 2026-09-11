from __future__ import annotations

import json
import socket
import sys
import tempfile
import unittest
import uuid
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

    @staticmethod
    def _synthetic_plan(
        master_count: int,
        *,
        barcodes_per_master: int = 1,
    ) -> dict[str, object]:
        masters = []
        barcodes = []
        barcode_sequence = 100_000
        for master_sequence in range(1, master_count + 1):
            master_id = str(uuid.UUID(int=master_sequence))
            masters.append(
                {
                    "record": {
                        "master_product_id": master_id,
                        "name": f"Product {master_sequence}",
                    },
                    "expected_version": None,
                }
            )
            for _ in range(barcodes_per_master):
                barcode_sequence += 1
                barcodes.append(
                    {
                        "record": {
                            "barcode_id": str(uuid.UUID(int=barcode_sequence)),
                            "master_product_id": master_id,
                        },
                        "expected_version": None,
                    }
                )
        plan: dict[str, object] = {
            "plan_version": 1,
            "importer_version": importer.IMPORTER_VERSION,
            "dataset_version": "test-1",
            "import_batch_id": BATCH_ID,
            "snapshot_hash": "c" * 64,
            "ready_to_apply": True,
            "masters": {"inserts": masters, "updates": [], "no_ops": []},
            "barcodes": {"inserts": barcodes, "updates": [], "no_ops": []},
        }
        plan["plan_hash"] = importer.sha256_json(plan)
        return plan

    @staticmethod
    def _manifest(plan: dict[str, object]) -> dict[str, object]:
        return importer.build_execution_manifest(
            plan=plan,
            seed_sha256="a" * 64,
            barcodes_sha256="b" * 64,
        )

    @staticmethod
    def _rpc_result(payload: dict[str, object], status: str = "applied") -> dict[str, object]:
        return {
            "status": status,
            "import_batch_id": payload["p_import_batch_id"],
            "dataset_version": payload["p_dataset_version"],
            "request_hash": importer.expected_remote_request_hash(payload),
            "masters": {
                "inserted": len(payload["p_masters"]),
                "updated": 0,
                "no_op": 0,
            },
            "barcodes": {
                "inserted": len(payload["p_barcodes"]),
                "updated": 0,
                "no_op": 0,
            },
        }

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

    def test_15_one_master_and_barcode_produce_one_chunk(self) -> None:
        manifest = self._manifest(self._synthetic_plan(1))
        self.assertEqual(manifest["chunk_count"], 1)
        self.assertEqual(manifest["chunks"][0]["master_count"], 1)
        self.assertEqual(manifest["chunks"][0]["barcode_count"], 1)

    def test_16_one_hundred_masters_fit_one_chunk(self) -> None:
        manifest = self._manifest(self._synthetic_plan(100))
        self.assertEqual(manifest["chunk_count"], 1)
        self.assertEqual(manifest["chunks"][0]["master_count"], 100)

    def test_17_one_hundred_one_masters_produce_two_chunks(self) -> None:
        manifest = self._manifest(self._synthetic_plan(101))
        self.assertEqual(manifest["chunk_count"], 2)
        self.assertEqual(
            [chunk["master_count"] for chunk in manifest["chunks"]],
            [100, 1],
        )

    def test_18_commercial_scale_plan_produces_valid_chunks(self) -> None:
        manifest = self._manifest(self._synthetic_plan(1_149))
        self.assertEqual(manifest["chunk_count"], 12)
        self.assertEqual(manifest["masters_total"], 1_149)
        self.assertEqual(manifest["barcodes_total"], 1_149)

    def test_19_no_chunk_exceeds_master_limit(self) -> None:
        manifest = self._manifest(self._synthetic_plan(1_149))
        self.assertTrue(
            all(
                chunk["master_count"] <= importer.MAX_MASTERS_PER_CHUNK
                for chunk in manifest["chunks"]
            )
        )

    def test_20_no_chunk_exceeds_barcode_limit(self) -> None:
        manifest = self._manifest(
            self._synthetic_plan(201, barcodes_per_master=3)
        )
        self.assertTrue(
            all(
                chunk["barcode_count"] <= importer.MAX_BARCODES_PER_CHUNK
                for chunk in manifest["chunks"]
            )
        )

    def test_21_master_and_all_owned_barcodes_stay_together(self) -> None:
        plan = self._synthetic_plan(140, barcodes_per_master=4)
        manifest = self._manifest(plan)
        barcode_owner = {
            entry["record"]["barcode_id"]: entry["record"]["master_product_id"]
            for entry in plan["barcodes"]["inserts"]
        }
        for chunk in manifest["chunks"]:
            chunk_masters = set(chunk["master_ids"])
            self.assertTrue(
                all(barcode_owner[barcode_id] in chunk_masters for barcode_id in chunk["barcode_ids"])
            )

    def test_22_multiple_barcodes_per_master_are_supported(self) -> None:
        manifest = self._manifest(self._synthetic_plan(3, barcodes_per_master=7))
        self.assertEqual(manifest["chunk_count"], 1)
        self.assertEqual(manifest["chunks"][0]["barcode_count"], 21)

    def test_23_master_with_more_than_five_hundred_barcodes_fails_closed(self) -> None:
        with self.assertRaisesRegex(importer.ImporterError, "cannot fit"):
            self._manifest(self._synthetic_plan(1, barcodes_per_master=501))

    def test_24_chunking_is_deterministic(self) -> None:
        plan = self._synthetic_plan(234, barcodes_per_master=2)
        first = self._manifest(plan)
        second = self._manifest(deepcopy(plan))
        self.assertEqual(importer.stable_json(first), importer.stable_json(second))

    def test_25_child_batch_ids_are_stable(self) -> None:
        plan = self._synthetic_plan(101)
        first = self._manifest(plan)
        second = self._manifest(plan)
        self.assertEqual(
            [chunk["child_import_batch_id"] for chunk in first["chunks"]],
            [chunk["child_import_batch_id"] for chunk in second["chunks"]],
        )

    def test_26_prepare_rerun_verifies_same_manifest_without_rewrite(self) -> None:
        snapshot = self._empty_snapshot()
        plan = self._plan(snapshot)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "execution.json"
            first, first_created = importer.prepare_execution_manifest(
                plan=plan,
                snapshot=snapshot,
                validation_report=self._report(),
                masters_path=VALID / "master_catalog_seed.csv",
                barcodes_path=VALID / "master_catalog_barcodes.csv",
                output_path=output,
            )
            before = output.read_bytes()
            second, second_created = importer.prepare_execution_manifest(
                plan=plan,
                snapshot=snapshot,
                validation_report=self._report(),
                masters_path=VALID / "master_catalog_seed.csv",
                barcodes_path=VALID / "master_catalog_barcodes.csv",
                output_path=output,
            )
            self.assertTrue(first_created)
            self.assertFalse(second_created)
            self.assertEqual(first, second)
            self.assertEqual(before, output.read_bytes())

    def test_27_stale_dataset_hash_manifest_is_rejected(self) -> None:
        plan = self._synthetic_plan(1)
        manifest = self._manifest(plan)
        with self.assertRaisesRegex(importer.ImporterError, "seed_sha256"):
            importer.validate_execution_manifest(
                manifest,
                plan=plan,
                seed_sha256="d" * 64,
                barcodes_sha256="b" * 64,
            )

    def test_28_stale_plan_hash_manifest_is_rejected(self) -> None:
        plan = self._synthetic_plan(1)
        manifest = self._manifest(plan)
        changed = deepcopy(plan)
        changed["review_note"] = "different approved plan"
        changed["plan_hash"] = importer.sha256_json(
            {key: value for key, value in changed.items() if key != "plan_hash"}
        )
        with self.assertRaisesRegex(importer.ImporterError, "plan_hash"):
            importer.validate_execution_manifest(
                manifest,
                plan=changed,
                seed_sha256="a" * 64,
                barcodes_sha256="b" * 64,
            )

    def test_29_stale_snapshot_hash_manifest_is_rejected(self) -> None:
        plan = self._synthetic_plan(1)
        manifest = self._manifest(plan)
        changed = deepcopy(plan)
        changed["snapshot_hash"] = "e" * 64
        changed["plan_hash"] = importer.sha256_json(
            {key: value for key, value in changed.items() if key != "plan_hash"}
        )
        with self.assertRaisesRegex(importer.ImporterError, "snapshot_hash"):
            importer.validate_execution_manifest(
                manifest,
                plan=changed,
                seed_sha256="a" * 64,
                barcodes_sha256="b" * 64,
            )

    def test_30_retry_reuses_same_child_id_and_exact_payload(self) -> None:
        plan = self._synthetic_plan(1)
        manifest = self._manifest(plan)
        payloads: list[dict[str, object]] = []
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "execution.json"
            importer.write_json_atomic(path, manifest)

            def fail_rpc(_name: str, payload: dict[str, object]) -> dict[str, object]:
                payloads.append(deepcopy(payload))
                raise RuntimeError("simulated transport failure")

            with self.assertRaises(importer.ImporterError):
                importer.apply_execution_manifest(
                    plan=plan,
                    manifest=manifest,
                    manifest_path=path,
                    seed_sha256="a" * 64,
                    barcodes_sha256="b" * 64,
                    rpc=fail_rpc,
                )

            def pass_rpc(_name: str, payload: dict[str, object]) -> dict[str, object]:
                payloads.append(deepcopy(payload))
                return self._rpc_result(payload, status="already_applied")

            importer.apply_execution_manifest(
                plan=plan,
                manifest=importer.read_json(path),
                manifest_path=path,
                seed_sha256="a" * 64,
                barcodes_sha256="b" * 64,
                rpc=pass_rpc,
            )
        self.assertEqual(payloads[0], payloads[1])

    def test_31_child_id_is_never_reused_for_different_payload(self) -> None:
        first_plan = self._synthetic_plan(1)
        second_plan = deepcopy(first_plan)
        second_plan["masters"]["inserts"][0]["record"]["name"] = "Changed"
        second_plan["plan_hash"] = importer.sha256_json(
            {key: value for key, value in second_plan.items() if key != "plan_hash"}
        )
        first = self._manifest(first_plan)
        second = self._manifest(second_plan)
        self.assertNotEqual(
            first["chunks"][0]["child_import_batch_id"],
            second["chunks"][0]["child_import_batch_id"],
        )
        self.assertNotEqual(
            first["chunks"][0]["payload_hash"],
            second["chunks"][0]["payload_hash"],
        )

    def test_32_remote_success_local_crash_retries_idempotently(self) -> None:
        class SimulatedCrash(BaseException):
            pass

        plan = self._synthetic_plan(1)
        manifest = self._manifest(plan)
        payloads: list[dict[str, object]] = []
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "execution.json"
            importer.write_json_atomic(path, manifest)

            def rpc(_name: str, payload: dict[str, object]) -> dict[str, object]:
                payloads.append(deepcopy(payload))
                status = "applied" if len(payloads) == 1 else "already_applied"
                return self._rpc_result(payload, status=status)

            with self.assertRaises(SimulatedCrash):
                importer.apply_execution_manifest(
                    plan=plan,
                    manifest=manifest,
                    manifest_path=path,
                    seed_sha256="a" * 64,
                    barcodes_sha256="b" * 64,
                    rpc=rpc,
                    after_rpc=lambda _index, _result: (_ for _ in ()).throw(SimulatedCrash()),
                )
            self.assertEqual(importer.read_json(path)["chunks"][0]["status"], "in_flight")
            importer.apply_execution_manifest(
                plan=plan,
                manifest=importer.read_json(path),
                manifest_path=path,
                seed_sha256="a" * 64,
                barcodes_sha256="b" * 64,
                rpc=rpc,
            )
        self.assertEqual(payloads[0], payloads[1])

    def test_33_failure_stops_before_the_next_chunk(self) -> None:
        plan = self._synthetic_plan(201)
        manifest = self._manifest(plan)
        called_chunks: list[str] = []
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "execution.json"
            importer.write_json_atomic(path, manifest)

            def rpc(_name: str, payload: dict[str, object]) -> dict[str, object]:
                called_chunks.append(payload["p_import_batch_id"])
                if len(called_chunks) == 2:
                    raise RuntimeError("chunk two failed")
                return self._rpc_result(payload)

            with self.assertRaises(importer.ImporterError):
                importer.apply_execution_manifest(
                    plan=plan,
                    manifest=manifest,
                    manifest_path=path,
                    seed_sha256="a" * 64,
                    barcodes_sha256="b" * 64,
                    rpc=rpc,
                )
            state = importer.read_json(path)
        self.assertEqual(len(called_chunks), 2)
        self.assertEqual(state["chunks"][2]["status"], "pending")

    def test_34_completed_chunks_do_not_become_new_operations(self) -> None:
        plan = self._synthetic_plan(101)
        manifest = self._manifest(plan)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "execution.json"
            importer.write_json_atomic(path, manifest)
            importer.apply_execution_manifest(
                plan=plan,
                manifest=manifest,
                manifest_path=path,
                seed_sha256="a" * 64,
                barcodes_sha256="b" * 64,
                rpc=lambda _name, payload: self._rpc_result(payload),
            )
            calls = 0

            def unexpected_rpc(_name: str, _payload: dict[str, object]) -> dict[str, object]:
                nonlocal calls
                calls += 1
                raise AssertionError("completed chunk was submitted again")

            result = importer.apply_execution_manifest(
                plan=plan,
                manifest=importer.read_json(path),
                manifest_path=path,
                seed_sha256="a" * 64,
                barcodes_sha256="b" * 64,
                rpc=unexpected_rpc,
            )
        self.assertEqual(calls, 0)
        self.assertEqual(result["completed_chunks"], 2)

    def test_35_manifest_preparation_does_not_change_datasets(self) -> None:
        masters = VALID / "master_catalog_seed.csv"
        barcodes = VALID / "master_catalog_barcodes.csv"
        before = (masters.read_bytes(), barcodes.read_bytes())
        snapshot = self._empty_snapshot()
        with tempfile.TemporaryDirectory() as directory:
            importer.prepare_execution_manifest(
                plan=self._plan(snapshot),
                snapshot=snapshot,
                validation_report=self._report(),
                masters_path=masters,
                barcodes_path=barcodes,
                output_path=Path(directory) / "execution.json",
            )
        self.assertEqual(before, (masters.read_bytes(), barcodes.read_bytes()))

    def test_36_execution_manifest_contains_no_secrets(self) -> None:
        serialized = importer.stable_json(self._manifest(self._synthetic_plan(2)))
        for forbidden in (
            "service_role",
            "supabase_service_role_key",
            "authorization",
            "bearer ",
            "password",
            "https://",
        ):
            self.assertNotIn(forbidden, serialized.lower())

    def test_37_expected_request_hash_matches_p1_3_backend_fixture(self) -> None:
        payload = {
            "p_import_batch_id": "11111111-1111-4111-8111-111111111111",
            "p_dataset_version": "test-1",
            "p_masters": [{
                "master_product_id": "00000000-0000-0000-0000-000000000001",
                "name": "Product 1",
                "expected_version": None,
            }],
            "p_barcodes": [{
                "barcode_id": "00000000-0000-0000-0000-0000000186a1",
                "master_product_id": "00000000-0000-0000-0000-000000000001",
                "expected_version": None,
            }],
        }
        expected = "8c9502b32def8d6626c102391a27176e5635ac6bb6da4bf122faa5fcc9c365c0"
        self.assertEqual(importer.expected_remote_request_hash(payload), expected)
        payload["p_import_batch_id"] = "22222222-2222-4222-8222-222222222222"
        self.assertEqual(importer.expected_remote_request_hash(payload), expected)

    def test_38_malformed_remote_responses_fail_closed(self) -> None:
        cases = {
            "wrong request_hash": lambda result: result.update({"request_hash": "f" * 64}),
            "missing request_hash": lambda result: result.pop("request_hash"),
            "missing required count": lambda result: result["masters"].pop("no_op"),
            "invalid count type": lambda result: result["masters"].update({"updated": "0"}),
            "negative count": lambda result: result["masters"].update({"updated": -1}),
            "incompatible exact counts": lambda result: result["masters"].update(
                {"inserted": 99, "updated": 1}
            ),
            "unknown status": lambda result: result.update({"status": "unexpected"}),
            "wrong child": lambda result: result.update(
                {"import_batch_id": "22222222-2222-4222-8222-222222222222"}
            ),
            "already_applied wrong hash": lambda result: result.update(
                {"status": "already_applied", "request_hash": "e" * 64}
            ),
        }
        for label, mutate in cases.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as directory:
                plan = self._synthetic_plan(101)
                manifest = self._manifest(plan)
                path = Path(directory) / "execution.json"
                importer.write_json_atomic(path, manifest)
                calls = 0

                def rpc(_name: str, payload: dict[str, object]) -> dict[str, object]:
                    nonlocal calls
                    calls += 1
                    result = self._rpc_result(payload)
                    mutate(result)
                    return result

                with self.assertRaises(importer.ImporterError):
                    importer.apply_execution_manifest(
                        plan=plan,
                        manifest=manifest,
                        manifest_path=path,
                        seed_sha256="a" * 64,
                        barcodes_sha256="b" * 64,
                        rpc=rpc,
                    )
                state = importer.read_json(path)
                self.assertEqual(calls, 1)
                self.assertEqual(state["status"], "failed")
                self.assertEqual(state["chunks"][0]["status"], "failed")
                self.assertEqual(state["chunks"][1]["status"], "pending")
                self.assertNotIn("remote_result", state["chunks"][0])

    def test_39_invalid_response_retry_reuses_same_child_and_request(self) -> None:
        plan = self._synthetic_plan(101)
        manifest = self._manifest(plan)
        payloads: list[dict[str, object]] = []
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "execution.json"
            importer.write_json_atomic(path, manifest)

            def invalid_rpc(_name: str, payload: dict[str, object]) -> dict[str, object]:
                payloads.append(deepcopy(payload))
                result = self._rpc_result(payload)
                result["request_hash"] = "d" * 64
                return result

            with self.assertRaises(importer.ImporterError):
                importer.apply_execution_manifest(
                    plan=plan,
                    manifest=manifest,
                    manifest_path=path,
                    seed_sha256="a" * 64,
                    barcodes_sha256="b" * 64,
                    rpc=invalid_rpc,
                )

            def retry_rpc(_name: str, payload: dict[str, object]) -> dict[str, object]:
                payloads.append(deepcopy(payload))
                return self._rpc_result(payload, status="already_applied")

            importer.apply_execution_manifest(
                plan=plan,
                manifest=importer.read_json(path),
                manifest_path=path,
                seed_sha256="a" * 64,
                barcodes_sha256="b" * 64,
                rpc=retry_rpc,
            )
        self.assertEqual(payloads[0], payloads[1])

    def test_40_corrupt_manifest_fails_before_rpc(self) -> None:
        calls = 0
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "execution.json"
            path.write_text('{"manifest_version": 1,', encoding="utf-8")

            def rpc(_name: str, _payload: dict[str, object]) -> dict[str, object]:
                nonlocal calls
                calls += 1
                raise AssertionError("RPC must not run for a corrupt manifest")

            with self.assertRaises(importer.ImporterError):
                manifest = importer.read_json(path)
                importer.apply_execution_manifest(
                    plan=self._synthetic_plan(1),
                    manifest=manifest,
                    manifest_path=path,
                    seed_sha256="a" * 64,
                    barcodes_sha256="b" * 64,
                    rpc=rpc,
                )
        self.assertEqual(calls, 0)

    def test_41_different_root_batch_produces_different_child_id(self) -> None:
        first_plan = self._synthetic_plan(1)
        second_plan = deepcopy(first_plan)
        second_plan["import_batch_id"] = "44444444-4444-4444-8444-444444444444"
        second_plan["plan_hash"] = importer.sha256_json(
            {key: value for key, value in second_plan.items() if key != "plan_hash"}
        )
        first = self._manifest(first_plan)
        second = self._manifest(second_plan)
        self.assertEqual(first["chunks"][0]["payload_hash"], second["chunks"][0]["payload_hash"])
        self.assertNotEqual(
            first["chunks"][0]["child_import_batch_id"],
            second["chunks"][0]["child_import_batch_id"],
        )

    def test_42_exact_counts_accept_insert_update_and_no_op_plan(self) -> None:
        plan = self._synthetic_plan(3)
        for section in ("masters", "barcodes"):
            update = plan[section]["inserts"].pop()
            update["expected_version"] = 2
            plan[section]["updates"].append(update)
            no_op = plan[section]["inserts"].pop()
            no_op["expected_version"] = 3
            plan[section]["no_ops"].append(no_op)
        plan["plan_hash"] = importer.sha256_json(
            {key: value for key, value in plan.items() if key != "plan_hash"}
        )
        manifest = self._manifest(plan)

        def rpc(_name: str, payload: dict[str, object]) -> dict[str, object]:
            result = self._rpc_result(payload)
            result["masters"] = {"inserted": 1, "updated": 1, "no_op": 1}
            result["barcodes"] = {"inserted": 1, "updated": 1, "no_op": 1}
            return result

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "execution.json"
            importer.write_json_atomic(path, manifest)
            result = importer.apply_execution_manifest(
                plan=plan,
                manifest=manifest,
                manifest_path=path,
                seed_sha256="a" * 64,
                barcodes_sha256="b" * 64,
                rpc=rpc,
            )
        self.assertEqual(result["completed_chunks"], 1)


if __name__ == "__main__":
    unittest.main()
