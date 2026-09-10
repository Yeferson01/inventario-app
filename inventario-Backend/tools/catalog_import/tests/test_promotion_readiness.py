from __future__ import annotations

import csv
import io
import json
import socket
import sqlite3
import sys
import tempfile
import unittest
import uuid
from contextlib import redirect_stdout
from decimal import Decimal
from pathlib import Path
from unittest import mock


TOOL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL_DIR))

import catalog_tool  # noqa: E402
from resolution import candidate_resolution  # noqa: E402
from resolution import category_mapping  # noqa: E402
from resolution import promotion_readiness as tool  # noqa: E402


class PromotionReadinessTest(unittest.TestCase):
    BARCODES = [
        ("01234565", "ean8"),
        ("036000291452", "upc"),
        ("4006381333931", "ean13"),
        ("5901234123457", "ean13"),
        ("96385074", "ean8"),
        ("10012345000017", "gtin"),
    ]

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.resolution = self.root / "resolution.csv"
        self.mapping = self.root / "mapping.csv"
        self.technical = self.root / "technical-ready.csv"
        self.master = self.root / "master-ready.csv"
        self.blocked = self.root / "blocked.csv"
        self.metrics = self.root / "metrics.json"

    @staticmethod
    def _resolution_row(
        barcode: str = "4006381333931",
        barcode_type: str = "ean13",
        **overrides: str,
    ) -> dict[str, str]:
        row = {
            "barcode": barcode,
            "barcode_type": barcode_type,
            "candidate_name_if_known": " Candidate name ",
            "candidate_brand_if_known": " Candidate brand ",
            "off_product_name": "OFF Product",
            "off_brands": "OFF Brand",
            "off_categories_tags": "en:foods,en:snacks",
            "off_main_category": "en:snacks",
            "off_quantity": "6 x 330 ml",
            "off_last_modified_t": "1788800000",
            "name_status": "available",
            "brand_status": "available",
            "category_status": "available",
            "quantity_status": "available",
            "source_match_status": "matched",
            "off_source_row_count": "1",
            "candidate_source_reference": "open-food-facts:snapshot:test",
            "candidate_source_content_sha256": "a" * 64,
            "off_source_content_sha256": "b" * 64,
            "retrieved_at": "2026-09-08T12:34:56-05:00",
            "rights_class": "open_dataset_odbl_share_alike",
            "rights_reference": "odbl:test",
            "resolution_record_sha256": "",
        }
        row.update(overrides)
        if "resolution_record_sha256" not in overrides:
            row["resolution_record_sha256"] = catalog_tool.record_hash(
                {
                    header: row[header]
                    for header in candidate_resolution.RESOLUTION_HEADERS
                    if header != "resolution_record_sha256"
                }
            )
        return row

    @staticmethod
    def _mapping_row(
        resolution: dict[str, str],
        *,
        status: str = "mapped",
        category: str = "Alimentos",
        reason: str = "exact_main_category_rule",
        **overrides: str,
    ) -> dict[str, str]:
        if status != "mapped" and category == "Alimentos":
            category = ""
        default_reasons = {
            "review": "review_required",
            "unresolved": "no_matching_rule",
            "excluded": "out_of_scope_for_initial_catalog",
        }
        if status != "mapped" and reason == "exact_main_category_rule":
            reason = default_reasons[status]
        row = {
            "barcode": resolution["barcode"],
            "off_main_category": resolution["off_main_category"],
            "off_categories_tags": resolution["off_categories_tags"],
            "cronos_category_candidate": category,
            "mapping_status": status,
            "mapping_rule_ids": "map-test" if status == "mapped" else "",
            "matched_off_tags": resolution["off_main_category"] if status == "mapped" else "",
            "mapping_reason": reason,
            "ruleset_version": "1.2.0",
            "ruleset_sha256": "c" * 64,
            "resolution_record_sha256": resolution["resolution_record_sha256"],
            "category_mapping_record_sha256": "",
        }
        row.update(overrides)
        if "category_mapping_record_sha256" not in overrides:
            row["category_mapping_record_sha256"] = catalog_tool.record_hash(
                {
                    header: row[header]
                    for header in category_mapping.CATEGORY_MAPPING_HEADERS
                    if header != "category_mapping_record_sha256"
                }
            )
        return row

    @staticmethod
    def _write_csv(path: Path, headers: list[str], rows: list[dict[str, str]]) -> None:
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(
                handle,
                fieldnames=headers,
                extrasaction="ignore",
                lineterminator="\n",
            )
            writer.writeheader()
            writer.writerows(rows)

    def _write_inputs(
        self,
        resolutions: list[dict[str, str]],
        mappings: list[dict[str, str]] | None = None,
        *,
        resolution_headers: list[str] | None = None,
        mapping_headers: list[str] | None = None,
    ) -> None:
        if mappings is None:
            mappings = [self._mapping_row(row) for row in resolutions]
        self._write_csv(
            self.resolution,
            resolution_headers or candidate_resolution.RESOLUTION_HEADERS,
            resolutions,
        )
        self._write_csv(
            self.mapping,
            mapping_headers or category_mapping.CATEGORY_MAPPING_HEADERS,
            mappings,
        )

    def _build(self) -> dict[str, object]:
        return tool.build_readiness(
            resolution_path=self.resolution,
            mapping_path=self.mapping,
            technical_ready_path=self.technical,
            master_ready_path=self.master,
            blocked_path=self.blocked,
            metrics_path=self.metrics,
        )

    @staticmethod
    def _csv_rows(path: Path) -> list[dict[str, str]]:
        with path.open("r", encoding="utf-8", newline="") as handle:
            return list(csv.DictReader(handle))

    def _single_ready(
        self, resolution: dict[str, str] | None = None
    ) -> tuple[dict[str, object], dict[str, str]]:
        self._write_inputs([resolution or self._resolution_row()])
        metrics = self._build()
        return metrics, self._csv_rows(self.technical)[0]

    def test_01_mapped_with_name_is_technical_ready(self) -> None:
        metrics, row = self._single_ready()
        self.assertEqual(metrics["technical_ready"], 1)
        self.assertEqual(metrics["technical_blocked"], 0)
        self.assertEqual(row["primary_barcode"], "4006381333931")
        self.assertNotIn("master_product_id", row)
        with self.technical.open("r", encoding="utf-8", newline="") as handle:
            self.assertEqual(csv.DictReader(handle).fieldnames, tool.TECHNICAL_READY_HEADERS)

    def test_02_non_mapped_statuses_are_blocked(self) -> None:
        statuses = ["review", "unresolved", "excluded"]
        resolutions = [
            self._resolution_row(barcode, barcode_type)
            for barcode, barcode_type in self.BARCODES[:3]
        ]
        mappings = [
            self._mapping_row(resolution, status=status)
            for resolution, status in zip(resolutions, statuses, strict=True)
        ]
        self._write_inputs(resolutions, mappings)
        self._build()
        blocked = self._csv_rows(self.blocked)
        self.assertEqual(len(blocked), 3)
        with self.blocked.open("r", encoding="utf-8", newline="") as handle:
            self.assertEqual(csv.DictReader(handle).fieldnames, tool.BLOCKED_HEADERS)
        for row, status in zip(blocked, statuses, strict=True):
            self.assertEqual(row["mapping_status"], status)
            self.assertEqual(row["technical_reason"], "category_not_mapped")

    def test_03_mapped_without_any_name_is_blocked(self) -> None:
        resolution = self._resolution_row(
            candidate_name_if_known="  ", off_product_name=""
        )
        self._write_inputs([resolution])
        self._build()
        row = self._csv_rows(self.blocked)[0]
        self.assertEqual(row["technical_reason"], "missing_name")
        self.assertEqual(row["has_name"], "false")

    def test_04_blocked_reason_precedence_is_fail_closed(self) -> None:
        resolutions = [
            self._resolution_row(
                "01234565",
                "ean8",
                candidate_source_reference="",
                candidate_name_if_known="",
                off_product_name="",
            ),
            self._resolution_row(
                "036000291452",
                "upc",
                candidate_name_if_known="",
                off_product_name="",
            ),
            self._resolution_row(
                "4006381333931",
                "ean13",
                candidate_name_if_known="",
                off_product_name="",
            ),
        ]
        mappings = [
            self._mapping_row(resolutions[0], status="review"),
            self._mapping_row(resolutions[1], status="unresolved"),
            self._mapping_row(resolutions[2]),
        ]
        self._write_inputs(resolutions, mappings)
        self._build()
        reasons = [row["technical_reason"] for row in self._csv_rows(self.blocked)]
        self.assertEqual(
            reasons,
            ["invalid_input_provenance", "category_not_mapped", "missing_name"],
        )

    def test_05_candidate_name_has_priority_and_only_exterior_trim(self) -> None:
        resolution = self._resolution_row(
            candidate_name_if_known="  Candidate   name  ",
            off_product_name="Different OFF name",
        )
        _, row = self._single_ready(resolution)
        self.assertEqual(row["name"], "Candidate   name")

    def test_06_off_name_is_the_only_fallback(self) -> None:
        resolution = self._resolution_row(
            candidate_name_if_known="", off_product_name="  OFF factual name  "
        )
        _, row = self._single_ready(resolution)
        self.assertEqual(row["name"], "OFF factual name")

    def test_07_brand_priority_fallback_and_empty_are_non_blocking(self) -> None:
        resolutions = [
            self._resolution_row(
                "01234565", "ean8", candidate_brand_if_known=" Candidate brand ", off_brands="OFF"
            ),
            self._resolution_row(
                "036000291452", "upc", candidate_brand_if_known="", off_brands=" OFF brand "
            ),
            self._resolution_row(
                "4006381333931", "ean13", candidate_brand_if_known="", off_brands=""
            ),
        ]
        self._write_inputs(resolutions)
        metrics = self._build()
        brands = [row["brand"] for row in self._csv_rows(self.technical)]
        self.assertEqual(brands, ["Candidate brand", "OFF brand", ""])
        self.assertEqual(metrics["technical_ready_with_brand"], 2)
        self.assertEqual(metrics["technical_ready_without_brand"], 1)

    def test_08_category_and_conservative_package_contract_are_exact(self) -> None:
        resolution = self._resolution_row(off_quantity="Bottle 750 ml")
        mapping = self._mapping_row(resolution, category="Bebidas")
        self._write_inputs([resolution], [mapping])
        self._build()
        row = self._csv_rows(self.technical)[0]
        self.assertEqual(row["category_name"], "Bebidas")
        self.assertEqual(row["package_size"], "")
        self.assertEqual(row["package_unit"], "")
        self.assertEqual(row["unit_type"], "unidad")

    def test_09_fixed_values_are_compatible_with_p12(self) -> None:
        vocabularies = catalog_tool._load_vocabularies(catalog_tool.DEFAULT_CONFIG)  # noqa: SLF001
        self.assertIn(tool.UNIT_TYPE, vocabularies["unit_types"])
        self.assertIn(tool.SOURCE, vocabularies["sources"])
        self.assertIn(tool.VERIFICATION_STATUS, vocabularies["verification_statuses"])
        self.assertGreaterEqual(Decimal(tool.TECHNICAL_CONFIDENCE_SCORE_V1), 0)
        self.assertLessEqual(Decimal(tool.TECHNICAL_CONFIDENCE_SCORE_V1), 1)
        _, row = self._single_ready()
        self.assertEqual(row["source"], "open_dataset")
        self.assertEqual(row["verification_status"], "unverified")
        self.assertEqual(row["confidence_score"], "0.70")

    def test_10_provenance_and_rights_are_preserved(self) -> None:
        resolution = self._resolution_row(
            candidate_source_reference="source:exact",
            rights_reference="rights:exact",
        )
        mapping = self._mapping_row(resolution)
        self._write_inputs([resolution], [mapping])
        self._build()
        row = self._csv_rows(self.technical)[0]
        self.assertEqual(row["source_reference"], "source:exact")
        self.assertEqual(row["rights_class"], "open_dataset_odbl_share_alike")
        self.assertEqual(row["rights_reference"], "rights:exact")
        self.assertEqual(row["resolution_record_sha256"], resolution["resolution_record_sha256"])
        self.assertEqual(
            row["category_mapping_record_sha256"],
            mapping["category_mapping_record_sha256"],
        )

    def test_11_invalid_semantic_provenance_is_blocked(self) -> None:
        cases = [
            {"source_match_status": "missing"},
            {"candidate_source_reference": ""},
            {"rights_reference": ""},
            {"rights_class": "unknown"},
            {"candidate_source_content_sha256": "invalid"},
            {"off_source_content_sha256": "invalid"},
            {"retrieved_at": ""},
            {"barcode_type": "invalid"},
            {"barcode": "4006381333932"},
        ]
        for overrides in cases:
            with self.subTest(overrides=overrides):
                resolution = self._resolution_row(**overrides)
                self._write_inputs([resolution])
                self._build()
                row = self._csv_rows(self.blocked)[0]
                self.assertEqual(row["technical_reason"], "invalid_input_provenance")

    def test_12_odbl_is_sidecar_only_and_master_output_is_header_only(self) -> None:
        metrics, _ = self._single_ready()
        self.assertEqual(metrics["rights_odbl_sidecar_only"], 1)
        self.assertEqual(metrics["rights_promotion_compatible"], 0)
        self.assertEqual(metrics["master_promotion_ready"], 0)
        self.assertEqual(metrics["master_promotion_blocked_rights"], 1)
        with self.master.open("r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            self.assertEqual(reader.fieldnames, tool.MASTER_PROMOTION_HEADERS)
            self.assertEqual(
                tool.MASTER_PROMOTION_HEADERS,
                [
                    *tool.TECHNICAL_READY_HEADERS,
                    "promotion_rights_status",
                    "promotion_reason",
                ],
            )
            self.assertEqual(list(reader), [])

    def test_13_master_gate_is_derived_from_rights_status(self) -> None:
        self._write_inputs([self._resolution_row()])
        with mock.patch.dict(
            tool.RIGHTS_STATUS_BY_CLASS,
            {"open_dataset_odbl_share_alike": "promotion_compatible"},
            clear=True,
        ):
            metrics = self._build()
        rows = self._csv_rows(self.master)
        self.assertEqual(metrics["master_promotion_ready"], 1)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["promotion_rights_status"], "promotion_compatible")
        self.assertEqual(rows[0]["promotion_reason"], tool.PROMOTION_REASON)

    def test_14_invalid_resolution_hash_blocks_build(self) -> None:
        resolution = self._resolution_row(resolution_record_sha256="d" * 64)
        self._write_inputs([resolution])
        with self.assertRaisesRegex(tool.PromotionReadinessValidationError, "resolution_record"):
            self._build()

    def test_15_invalid_mapping_hash_blocks_build(self) -> None:
        resolution = self._resolution_row()
        mapping = self._mapping_row(
            resolution, category_mapping_record_sha256="d" * 64
        )
        self._write_inputs([resolution], [mapping])
        with self.assertRaisesRegex(
            tool.PromotionReadinessValidationError, "category_mapping_record"
        ):
            self._build()

    def test_16_different_barcode_sets_block_build(self) -> None:
        resolution = self._resolution_row()
        other = self._resolution_row("5901234123457", "ean13")
        self._write_inputs([resolution], [self._mapping_row(other)])
        with self.assertRaisesRegex(tool.PromotionReadinessValidationError, "sets are different"):
            self._build()

    def test_17_duplicate_barcodes_block_build(self) -> None:
        resolution = self._resolution_row()
        for duplicate_side in ("resolution", "mapping"):
            with self.subTest(duplicate_side=duplicate_side):
                resolutions = [resolution, resolution] if duplicate_side == "resolution" else [resolution]
                mapping = self._mapping_row(resolution)
                mappings = [mapping, mapping] if duplicate_side == "mapping" else [mapping]
                self._write_inputs(resolutions, mappings)
                with self.assertRaisesRegex(tool.PromotionReadinessValidationError, "Duplicate"):
                    self._build()

    def test_18_empty_barcode_and_incompatible_headers_fail_closed(self) -> None:
        empty = self._resolution_row("", "ean13")
        self._write_inputs([empty])
        with self.assertRaisesRegex(tool.PromotionReadinessValidationError, "empty barcode"):
            self._build()

        valid = self._resolution_row()
        self._write_inputs(
            [valid],
            resolution_headers=candidate_resolution.RESOLUTION_HEADERS[:-1],
        )
        with self.assertRaisesRegex(tool.PromotionReadinessValidationError, "header"):
            self._build()

        self._write_inputs(
            [valid],
            mapping_headers=category_mapping.CATEGORY_MAPPING_HEADERS[:-1],
        )
        with self.assertRaisesRegex(tool.PromotionReadinessValidationError, "header"):
            self._build()

    def test_19_mapping_resolution_hash_linkage_is_required(self) -> None:
        resolution = self._resolution_row()
        mapping = self._mapping_row(resolution, resolution_record_sha256="e" * 64)
        self._write_inputs([resolution], [mapping])
        with self.assertRaisesRegex(tool.PromotionReadinessValidationError, "provenance"):
            self._build()

    def test_20_outputs_are_sorted_and_byte_deterministic(self) -> None:
        resolutions = [
            self._resolution_row(barcode, barcode_type)
            for barcode, barcode_type in reversed(self.BARCODES[:4])
        ]
        mappings = [
            self._mapping_row(row, status="review") if index == 1 else self._mapping_row(row)
            for index, row in enumerate(resolutions)
        ]
        self._write_inputs(resolutions, mappings)
        self._build()
        paths = [self.technical, self.master, self.blocked, self.metrics]
        first = {path.name: path.read_bytes() for path in paths}
        self.assertEqual(
            [row["primary_barcode"] for row in self._csv_rows(self.technical)],
            sorted(row["barcode"] for row, mapping in zip(resolutions, mappings) if mapping["mapping_status"] == "mapped"),
        )

        self._write_inputs(list(reversed(resolutions)), list(reversed(mappings)))
        self._build()
        self.assertEqual(first, {path.name: path.read_bytes() for path in paths})

    def test_21_readiness_hash_is_deterministic_and_covers_factual_record(self) -> None:
        _, first = self._single_ready()
        first_hash = first["readiness_record_sha256"]
        _, repeated = self._single_ready()
        self.assertEqual(repeated["readiness_record_sha256"], first_hash)

        changed = self._resolution_row(candidate_name_if_known="Changed factual name")
        _, changed_row = self._single_ready(changed)
        self.assertNotEqual(changed_row["readiness_record_sha256"], first_hash)
        self.assertEqual(
            changed_row["readiness_record_sha256"],
            catalog_tool.record_hash(
                {
                    header: changed_row[header]
                    for header in tool.TECHNICAL_READY_HEADERS
                    if header != "readiness_record_sha256"
                }
            ),
        )

    def test_22_validation_failure_preserves_every_prior_output(self) -> None:
        self._write_inputs([self._resolution_row()])
        paths = [self.technical, self.master, self.blocked, self.metrics]
        for path in paths:
            path.write_text(f"existing-{path.name}\n", encoding="utf-8")
        with mock.patch.object(
            tool,
            "_validate_master_output",
            side_effect=tool.PromotionReadinessValidationError("forced"),
        ):
            with self.assertRaisesRegex(tool.PromotionReadinessValidationError, "forced"):
                self._build()
        for path in paths:
            self.assertEqual(
                path.read_text(encoding="utf-8"), f"existing-{path.name}\n"
            )

    def test_23_input_failure_preserves_every_prior_output(self) -> None:
        resolution = self._resolution_row(resolution_record_sha256="f" * 64)
        self._write_inputs([resolution])
        paths = [self.technical, self.master, self.blocked, self.metrics]
        for path in paths:
            path.write_text("existing\n", encoding="utf-8")
        with self.assertRaises(tool.PromotionReadinessValidationError):
            self._build()
        for path in paths:
            self.assertEqual(path.read_text(encoding="utf-8"), "existing\n")

    def test_24_output_paths_are_safe_and_distinct(self) -> None:
        self._write_inputs([self._resolution_row()])
        with self.assertRaisesRegex(tool.PromotionReadinessToolError, "distinct"):
            tool.build_readiness(
                resolution_path=self.resolution,
                mapping_path=self.mapping,
                technical_ready_path=self.technical,
                master_ready_path=self.technical,
                blocked_path=self.blocked,
                metrics_path=self.metrics,
            )
        with self.assertRaisesRegex(tool.PromotionReadinessToolError, "overwrite inputs"):
            tool.build_readiness(
                resolution_path=self.resolution,
                mapping_path=self.mapping,
                technical_ready_path=self.resolution,
                master_ready_path=self.master,
                blocked_path=self.blocked,
                metrics_path=self.metrics,
            )

    def test_25_no_network_database_uuid_allocation_or_p13_access(self) -> None:
        self._write_inputs([self._resolution_row()])
        with (
            mock.patch.object(socket, "socket", side_effect=AssertionError("network used")),
            mock.patch.object(sqlite3, "connect", side_effect=AssertionError("database used")),
            mock.patch.object(uuid, "uuid4", side_effect=AssertionError("uuid used")),
            mock.patch.object(
                catalog_tool, "allocate_ids", side_effect=AssertionError("allocate-ids used")
            ),
            mock.patch.dict(sys.modules, {"catalog_importer": None}),
        ):
            metrics = self._build()
        self.assertFalse(metrics["network_access"])
        self.assertFalse(metrics["database_access"])
        self.assertFalse(metrics["uuid_generation"])
        self.assertNotIn("master_product_id", tool.TECHNICAL_READY_HEADERS)

    def test_26_name_brand_and_package_are_not_inferred(self) -> None:
        resolution = self._resolution_row(
            candidate_name_if_known="",
            off_product_name="Product 12 bottles",
            candidate_brand_if_known="",
            off_brands="Brand A, Brand B",
            off_quantity="12 x 500 ml",
        )
        _, row = self._single_ready(resolution)
        self.assertEqual(row["name"], "Product 12 bottles")
        self.assertEqual(row["brand"], "Brand A, Brand B")
        self.assertEqual(row["package_size"], "")
        self.assertEqual(row["package_unit"], "")
        self.assertEqual(row["unit_type"], "unidad")

    def test_27_metrics_reconcile_a_synthetic_population(self) -> None:
        resolutions = [
            self._resolution_row("01234565", "ean8"),
            self._resolution_row(
                "036000291452", "upc", candidate_brand_if_known="", off_brands=""
            ),
            self._resolution_row("4006381333931", "ean13"),
            self._resolution_row(
                "5901234123457",
                "ean13",
                candidate_name_if_known="",
                off_product_name="",
            ),
            self._resolution_row(
                "96385074", "ean8", candidate_source_reference=""
            ),
        ]
        mappings = [
            self._mapping_row(resolutions[0], category="Alimentos"),
            self._mapping_row(resolutions[1], category="Bebidas"),
            self._mapping_row(resolutions[2], status="review"),
            self._mapping_row(resolutions[3], category="Snacks y confitería"),
            self._mapping_row(resolutions[4], category="Cuidado personal"),
        ]
        self._write_inputs(resolutions, mappings)
        metrics = self._build()
        expected = {
            "input_rows": 5,
            "category_mapped": 4,
            "category_not_mapped": 1,
            "with_name": 4,
            "missing_name": 1,
            "technical_ready": 2,
            "technical_blocked": 3,
            "technical_ready_alimentos": 1,
            "technical_ready_bebidas": 1,
            "technical_ready_snacks_y_confiteria": 0,
            "technical_ready_aseo_del_hogar": 0,
            "technical_ready_cuidado_personal": 0,
            "technical_ready_with_brand": 1,
            "technical_ready_without_brand": 1,
            "rights_odbl_sidecar_only": 2,
            "rights_promotion_compatible": 0,
            "master_promotion_ready": 0,
            "master_promotion_blocked_rights": 2,
            "unit_type_unidad": 2,
            "network_access": False,
            "database_access": False,
            "uuid_generation": False,
        }
        for key, value in expected.items():
            self.assertEqual(metrics[key], value, key)
        reasons = {
            row["barcode"]: row["technical_reason"] for row in self._csv_rows(self.blocked)
        }
        self.assertEqual(reasons["4006381333931"], "category_not_mapped")
        self.assertEqual(reasons["5901234123457"], "missing_name")
        self.assertEqual(reasons["96385074"], "invalid_input_provenance")

    def test_28_cli_prints_the_human_report(self) -> None:
        self._write_inputs([self._resolution_row()])
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            exit_code = tool.main(
                [
                    "build",
                    "--resolution",
                    str(self.resolution),
                    "--mapping",
                    str(self.mapping),
                    "--technical-ready",
                    str(self.technical),
                    "--master-ready",
                    str(self.master),
                    "--blocked",
                    str(self.blocked),
                    "--metrics",
                    str(self.metrics),
                ]
            )
        self.assertEqual(exit_code, 0)
        report = stdout.getvalue()
        self.assertIn("Promotion Readiness: SUCCESS", report)
        self.assertIn("Input rows: 1", report)
        self.assertIn("ODbL sidecar only: 1", report)
        self.assertIn("Master promotion ready: 0", report)


if __name__ == "__main__":
    unittest.main()
