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
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock


TOOL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL_DIR))

import catalog_tool  # noqa: E402
from resolution import master_seed_materializer as tool  # noqa: E402
from resolution import promotion_readiness  # noqa: E402


class MasterSeedMaterializerTest(unittest.TestCase):
    BARCODES = [
        ("01234565", "ean8"),
        ("036000291452", "upc"),
        ("4006381333931", "ean13"),
        ("5901234123457", "ean13"),
        ("10012345000017", "gtin"),
    ]

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.technical = self.root / "technical-ready.csv"
        self.existing = self.root / "master_catalog_seed.csv"
        self.output = self.root / "master-seed-provisional.csv"
        self.provenance = self.root / "master-seed-provenance.csv"
        self.conflicts = self.root / "conflicts.csv"
        self.metrics = self.root / "metrics.json"
        self._write_existing([])

    @staticmethod
    def _technical_row(
        barcode: str = "4006381333931",
        barcode_type: str = "ean13",
        **overrides: str,
    ) -> dict[str, str]:
        row = {
            "primary_barcode": barcode,
            "barcode_type": barcode_type,
            "name": "Producto de prueba",
            "brand": "Marca de prueba",
            "category_name": "Alimentos",
            "package_size": "",
            "package_unit": "",
            "unit_type": "unidad",
            "source": "open_dataset",
            "verification_status": "unverified",
            "confidence_score": "0.70",
            "source_reference": "open-food-facts:snapshot:test",
            "rights_class": "open_dataset_odbl_share_alike",
            "rights_reference": "odbl:https://opendatacommons.org/licenses/odbl/1-0/",
            "resolution_record_sha256": "a" * 64,
            "category_mapping_record_sha256": "b" * 64,
            "readiness_record_sha256": "",
        }
        row.update(overrides)
        if "readiness_record_sha256" not in overrides:
            row["readiness_record_sha256"] = catalog_tool.record_hash(
                {
                    header: row[header]
                    for header in promotion_readiness.TECHNICAL_READY_HEADERS
                    if header != "readiness_record_sha256"
                }
            )
        return row

    @staticmethod
    def _write_csv(
        path: Path, headers: list[str], rows: list[dict[str, str]]
    ) -> None:
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(
                handle,
                fieldnames=headers,
                extrasaction="ignore",
                lineterminator="\n",
            )
            writer.writeheader()
            writer.writerows(rows)

    def _write_technical(self, rows: list[dict[str, str]]) -> None:
        self._write_csv(
            self.technical, promotion_readiness.TECHNICAL_READY_HEADERS, rows
        )

    def _write_existing(self, rows: list[dict[str, str]]) -> None:
        self._write_csv(self.existing, catalog_tool.MASTER_HEADERS, rows)

    @staticmethod
    def _read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
        with path.open("r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            return list(reader.fieldnames or []), list(reader)

    def _build(self, *, allow: bool = True) -> dict[str, object]:
        return tool.build_materialization(
            technical_ready_path=self.technical,
            existing_seed_path=self.existing,
            output_path=self.output,
            provenance_path=self.provenance,
            conflicts_path=self.conflicts,
            metrics_path=self.metrics,
            allow_provisional_open_dataset=allow,
        )

    def test_01_override_is_required_and_no_output_is_published(self) -> None:
        self._write_technical([self._technical_row()])
        with self.assertRaises(tool.MasterSeedMaterializerToolError):
            self._build(allow=False)
        self.assertFalse(self.output.exists())
        self.assertFalse(self.provenance.exists())
        self.assertFalse(self.conflicts.exists())
        self.assertFalse(self.metrics.exists())

        stderr = io.StringIO()
        with redirect_stderr(stderr):
            exit_code = tool.main(
                [
                    "build",
                    "--technical-ready",
                    str(self.technical),
                    "--existing-seed",
                    str(self.existing),
                    "--output",
                    str(self.output),
                    "--provenance",
                    str(self.provenance),
                    "--conflicts",
                    str(self.conflicts),
                    "--metrics",
                    str(self.metrics),
                ]
            )
        self.assertNotEqual(exit_code, 0)
        self.assertIn("--allow-provisional-open-dataset", stderr.getvalue())
        self.assertFalse(self.output.exists())

    def test_02_valid_row_maps_exactly_to_master_contract(self) -> None:
        technical = self._technical_row(
            name="Café colombiano",
            brand="Marca Uno",
            category_name="Bebidas",
            source_reference="open-food-facts:snapshot:2026-09-08:4006381333931",
        )
        self._write_technical([technical])
        self._build()

        headers, rows = self._read_csv(self.output)
        self.assertEqual(headers, catalog_tool.MASTER_HEADERS)
        self.assertEqual(len(rows), 1)
        row = rows[0]
        expected_copies = {
            "primary_barcode": "4006381333931",
            "barcode_type": "ean13",
            "name": "Café colombiano",
            "brand": "Marca Uno",
            "category_name": "Bebidas",
            "unit_type": "unidad",
            "source": "open_dataset",
            "verification_status": "unverified",
            "confidence_score": "0.70",
            "source_reference": technical["source_reference"],
        }
        for field_name, expected in expected_copies.items():
            self.assertEqual(row[field_name], expected)
        for field_name in (
            "master_product_id",
            "manufacturer",
            "subcategory_name",
            "package_size",
            "package_unit",
            "description",
            "image_source_key",
            "image_license",
            "image_attribution",
        ):
            self.assertEqual(row[field_name], "")

    def test_03_leading_zero_and_barcode_type_are_preserved(self) -> None:
        self._write_technical([self._technical_row("01234565", "ean8")])
        self._build()
        _, rows = self._read_csv(self.output)
        self.assertEqual(rows[0]["primary_barcode"], "01234565")
        self.assertEqual(rows[0]["barcode_type"], "ean8")

    def test_04_empty_brand_is_allowed_and_not_used_as_manufacturer(self) -> None:
        self._write_technical([self._technical_row(brand="")])
        metrics = self._build()
        _, rows = self._read_csv(self.output)
        self.assertEqual(rows[0]["brand"], "")
        self.assertEqual(rows[0]["manufacturer"], "")
        self.assertEqual(metrics["with_brand"], 0)
        self.assertEqual(metrics["without_brand"], 1)

    def test_05_provenance_preserves_rights_and_all_upstream_hashes(self) -> None:
        technical = self._technical_row()
        self._write_technical([technical])
        self._build()
        headers, rows = self._read_csv(self.provenance)
        self.assertEqual(headers, tool.PROVENANCE_HEADERS)
        row = rows[0]
        self.assertEqual(row["materialization_mode"], tool.MATERIALIZATION_MODE)
        self.assertNotEqual(row["materialization_mode"], "promotion_compatible")
        for field_name in (
            "primary_barcode",
            "source",
            "source_reference",
            "rights_class",
            "rights_reference",
            "resolution_record_sha256",
            "category_mapping_record_sha256",
            "readiness_record_sha256",
        ):
            self.assertEqual(row[field_name], technical[field_name])
        self.assertRegex(row["materialization_record_sha256"], r"^[0-9a-f]{64}$")

    def test_06_materialization_hash_is_deterministic_and_covers_both_records(self) -> None:
        technical = self._technical_row()
        master = tool._master_row(technical)
        provenance = tool._provenance_without_materialization_hash(technical)
        first = tool.materialization_record_hash(master, provenance)
        second = tool.materialization_record_hash(dict(master), dict(provenance))
        self.assertEqual(first, second)

        changed_master = {**master, "name": "Nombre distinto"}
        self.assertNotEqual(
            first, tool.materialization_record_hash(changed_master, provenance)
        )
        changed_provenance = {**provenance, "rights_reference": "odbl:other"}
        self.assertNotEqual(
            first, tool.materialization_record_hash(master, changed_provenance)
        )

    def test_07_existing_barcode_is_isolated_as_a_conflict(self) -> None:
        technical = self._technical_row()
        self._write_technical([technical])
        self._write_existing(
            [{"primary_barcode": "4006381333931", "name": "Fila manual"}]
        )
        metrics = self._build()
        _, master_rows = self._read_csv(self.output)
        _, provenance_rows = self._read_csv(self.provenance)
        headers, conflict_rows = self._read_csv(self.conflicts)
        self.assertEqual(headers, tool.CONFLICT_HEADERS)
        self.assertEqual(master_rows, [])
        self.assertEqual(provenance_rows, [])
        self.assertEqual(
            conflict_rows,
            [
                {
                    "primary_barcode": "4006381333931",
                    "reason_code": "barcode_already_in_existing_seed",
                    "existing_seed_present": "true",
                    "incoming_name": technical["name"],
                    "incoming_category_name": technical["category_name"],
                    "incoming_source_reference": technical["source_reference"],
                }
            ],
        )
        self.assertEqual(metrics["barcode_conflicts_existing_seed"], 1)
        self.assertEqual(metrics["provisional_master_rows"], 0)

    def test_08_invalid_non_conflicting_existing_row_does_not_block_or_change(self) -> None:
        self._write_technical([self._technical_row()])
        self._write_existing(
            [
                {
                    "master_product_id": "not-a-uuid",
                    "primary_barcode": "not-a-global-barcode",
                    "name": "Manual WIP",
                    "category_name": "Not in vocabulary",
                }
            ]
        )
        before = self.existing.read_bytes()
        metrics = self._build()
        self.assertEqual(self.existing.read_bytes(), before)
        self.assertEqual(metrics["existing_seed_rows"], 1)
        self.assertEqual(metrics["existing_seed_unique_barcodes"], 1)
        self.assertEqual(metrics["provisional_master_rows"], 1)

    def test_09_normalized_existing_barcode_detects_collision(self) -> None:
        self._write_technical([self._technical_row()])
        self._write_existing([{"primary_barcode": " 4006-3813-33931 "}])
        metrics = self._build()
        self.assertEqual(metrics["barcode_conflicts_existing_seed"], 1)

    def test_10_duplicate_incoming_barcode_blocks_without_outputs(self) -> None:
        self._write_technical([self._technical_row(), self._technical_row()])
        with self.assertRaises(tool.MasterSeedMaterializerValidationError):
            self._build()
        self.assertFalse(self.output.exists())
        self.assertFalse(self.provenance.exists())

    def test_11_malformed_technical_header_and_row_block(self) -> None:
        self.technical.write_text("barcode,name\n4006381333931,Test\n", encoding="utf-8")
        with self.assertRaises(tool.MasterSeedMaterializerValidationError):
            self._build()

        self.technical.write_text(
            ",".join(promotion_readiness.TECHNICAL_READY_HEADERS)
            + "\n4006381333931,ean13\n",
            encoding="utf-8",
        )
        with self.assertRaises(tool.MasterSeedMaterializerValidationError):
            self._build()
        self.assertFalse(self.output.exists())

    def test_12_invalid_technical_contract_values_block(self) -> None:
        cases = [
            {"category_name": "Otra"},
            {"unit_type": "botella"},
            {"source": "manual_curated"},
            {"verification_status": "verified"},
            {"confidence_score": "0.90"},
            {"name": "  "},
            {"rights_class": ""},
            {"source_reference": ""},
            {"barcode_type": "EAN-13"},
            {"primary_barcode": "4006381333932"},
            {"package_size": "1", "package_unit": "unidad"},
        ]
        for overrides in cases:
            with self.subTest(overrides=overrides):
                row = self._technical_row(**overrides)
                self._write_technical([row])
                with self.assertRaises(tool.MasterSeedMaterializerValidationError):
                    self._build()
                self.assertFalse(self.output.exists())

    def test_13_invalid_readiness_and_upstream_hashes_block(self) -> None:
        for field_name in (
            "readiness_record_sha256",
            "resolution_record_sha256",
            "category_mapping_record_sha256",
        ):
            with self.subTest(field_name=field_name):
                self._write_technical(
                    [self._technical_row(**{field_name: "not-a-sha256"})]
                )
                with self.assertRaises(tool.MasterSeedMaterializerValidationError):
                    self._build()

        row = self._technical_row()
        row["readiness_record_sha256"] = "c" * 64
        self._write_technical([row])
        with self.assertRaises(tool.MasterSeedMaterializerValidationError):
            self._build()

    def test_14_master_and_provenance_are_one_to_one_and_sorted(self) -> None:
        rows = [
            self._technical_row("5901234123457", "ean13", name="Segundo"),
            self._technical_row("01234565", "ean8", name="Primero"),
            self._technical_row("4006381333931", "ean13", name="Tercero"),
        ]
        self._write_technical(rows)
        self._build()
        _, master_rows = self._read_csv(self.output)
        _, provenance_rows = self._read_csv(self.provenance)
        master_barcodes = [row["primary_barcode"] for row in master_rows]
        provenance_barcodes = [row["primary_barcode"] for row in provenance_rows]
        self.assertEqual(master_barcodes, sorted(master_barcodes))
        self.assertEqual(provenance_barcodes, master_barcodes)
        self.assertEqual(len(master_rows), len(provenance_rows))

    def test_15_outputs_are_byte_deterministic(self) -> None:
        self._write_technical(
            [
                self._technical_row("5901234123457", "ean13"),
                self._technical_row("01234565", "ean8"),
            ]
        )
        self._build()
        first = tuple(
            path.read_bytes()
            for path in (self.output, self.provenance, self.conflicts, self.metrics)
        )
        self._build()
        second = tuple(
            path.read_bytes()
            for path in (self.output, self.provenance, self.conflicts, self.metrics)
        )
        self.assertEqual(first, second)

    def test_16_metrics_reconcile_all_synthetic_dimensions(self) -> None:
        categories = [
            "Alimentos",
            "Bebidas",
            "Snacks y confitería",
            "Aseo del hogar",
            "Cuidado personal",
        ]
        rows = [
            self._technical_row(
                barcode,
                barcode_type,
                category_name=category,
                brand="Marca" if index % 2 == 0 else "",
            )
            for index, ((barcode, barcode_type), category) in enumerate(
                zip(self.BARCODES, categories, strict=True)
            )
        ]
        self._write_technical(rows)
        self._write_existing([{"primary_barcode": self.BARCODES[1][0]}])
        metrics = self._build()
        self.assertEqual(metrics["technical_ready_input"], 5)
        self.assertEqual(metrics["existing_seed_rows"], 1)
        self.assertEqual(metrics["existing_seed_unique_barcodes"], 1)
        self.assertEqual(metrics["provisional_master_rows"], 4)
        self.assertEqual(metrics["provenance_rows"], 4)
        self.assertEqual(metrics["barcode_conflicts_existing_seed"], 1)
        self.assertEqual(metrics["with_brand"], 3)
        self.assertEqual(metrics["without_brand"], 1)
        self.assertEqual(metrics["alimentos"], 1)
        self.assertEqual(metrics["bebidas"], 0)
        self.assertEqual(metrics["snacks_y_confiteria"], 1)
        self.assertEqual(metrics["aseo_del_hogar"], 1)
        self.assertEqual(metrics["cuidado_personal"], 1)
        self.assertEqual(metrics["ean13"], 2)
        self.assertEqual(metrics["ean8"], 1)
        self.assertEqual(metrics["upc"], 0)
        self.assertEqual(metrics["gtin14"], 1)
        self.assertEqual(metrics["source_open_dataset"], 4)
        self.assertEqual(metrics["verification_unverified"], 4)
        self.assertEqual(metrics["unit_type_unidad"], 4)
        self.assertIs(metrics["provisional_override_used"], True)
        self.assertIs(metrics["uuid_generation"], False)
        self.assertIs(metrics["database_access"], False)
        self.assertIs(metrics["network_access"], False)
        self.assertEqual(json.loads(self.metrics.read_text(encoding="utf-8")), metrics)

    def test_17_validation_failure_preserves_all_prior_outputs_atomically(self) -> None:
        self._write_technical([self._technical_row()])
        finals = (self.output, self.provenance, self.conflicts, self.metrics)
        for index, path in enumerate(finals):
            path.write_bytes(f"prior-{index}".encode("ascii"))
        before = tuple(path.read_bytes() for path in finals)

        with mock.patch.object(
            tool,
            "_validate_metrics_output",
            side_effect=tool.MasterSeedMaterializerValidationError("synthetic"),
        ):
            with self.assertRaises(tool.MasterSeedMaterializerValidationError):
                self._build()
        self.assertEqual(tuple(path.read_bytes() for path in finals), before)
        self.assertEqual(list(self.root.glob(".*.tmp")), [])

    def test_18_success_publishes_each_validated_file_with_atomic_replace(self) -> None:
        self._write_technical([self._technical_row()])
        replace = tool.os.replace
        with mock.patch.object(tool.os, "replace", wraps=replace) as replace_mock:
            self._build()
        self.assertEqual(replace_mock.call_count, 4)
        self.assertEqual(
            [Path(call.args[1]) for call in replace_mock.call_args_list],
            [self.output, self.provenance, self.conflicts, self.metrics],
        )
        self.assertTrue(
            all(Path(call.args[0]).suffix == ".tmp" for call in replace_mock.call_args_list)
        )

    def test_19_input_failure_preserves_prior_outputs(self) -> None:
        self._write_technical([self._technical_row(category_name="Invalid")])
        finals = (self.output, self.provenance, self.conflicts, self.metrics)
        for index, path in enumerate(finals):
            path.write_bytes(f"prior-{index}".encode("ascii"))
        before = tuple(path.read_bytes() for path in finals)
        with self.assertRaises(tool.MasterSeedMaterializerValidationError):
            self._build()
        self.assertEqual(tuple(path.read_bytes() for path in finals), before)

    def test_20_existing_seed_header_must_expose_primary_barcode(self) -> None:
        self._write_technical([self._technical_row()])
        self.existing.write_text("name\nManual WIP\n", encoding="utf-8")
        with self.assertRaises(tool.MasterSeedMaterializerValidationError):
            self._build()
        self.assertFalse(self.output.exists())

    def test_21_existing_seed_row_must_keep_primary_barcode_accessible(self) -> None:
        self._write_technical([self._technical_row()])
        self.existing.write_text(
            "name,primary_barcode\nManual WIP\n", encoding="utf-8"
        )
        with self.assertRaises(tool.MasterSeedMaterializerValidationError):
            self._build()
        self.assertFalse(self.output.exists())

    def test_22_outputs_cannot_overwrite_inputs_or_each_other(self) -> None:
        self._write_technical([self._technical_row()])
        with self.assertRaises(tool.MasterSeedMaterializerToolError):
            tool.build_materialization(
                technical_ready_path=self.technical,
                existing_seed_path=self.existing,
                output_path=self.technical,
                provenance_path=self.provenance,
                conflicts_path=self.conflicts,
                metrics_path=self.metrics,
                allow_provisional_open_dataset=True,
            )
        with self.assertRaises(tool.MasterSeedMaterializerToolError):
            tool.build_materialization(
                technical_ready_path=self.technical,
                existing_seed_path=self.existing,
                output_path=self.output,
                provenance_path=self.output,
                conflicts_path=self.conflicts,
                metrics_path=self.metrics,
                allow_provisional_open_dataset=True,
            )

    def test_23_cli_builds_synthetic_example_and_prints_human_report(self) -> None:
        self._write_technical([self._technical_row(category_name="Bebidas")])
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            exit_code = tool.main(
                [
                    "build",
                    "--technical-ready",
                    str(self.technical),
                    "--existing-seed",
                    str(self.existing),
                    "--output",
                    str(self.output),
                    "--provenance",
                    str(self.provenance),
                    "--conflicts",
                    str(self.conflicts),
                    "--metrics",
                    str(self.metrics),
                    "--allow-provisional-open-dataset",
                ]
            )
        self.assertEqual(exit_code, 0)
        report = stdout.getvalue()
        self.assertIn("Master Seed Materialization: SUCCESS", report)
        self.assertIn("Technical-ready input: 1", report)
        self.assertIn("Provisional master rows: 1", report)
        self.assertIn("provisional_open_dataset_override", report)
        self.assertIn("UUID generation: none", report)
        self.assertIn("Database access: none", report)
        self.assertIn("Network access: none", report)

    def test_24_build_performs_no_uuid_database_or_network_operation(self) -> None:
        self._write_technical([self._technical_row()])
        with (
            mock.patch.object(uuid, "uuid4", side_effect=AssertionError("UUID used")),
            mock.patch.object(
                sqlite3, "connect", side_effect=AssertionError("database used")
            ),
            mock.patch.object(
                socket, "create_connection", side_effect=AssertionError("network used")
            ),
        ):
            self._build()
        source = Path(tool.__file__).read_text(encoding="utf-8")
        self.assertNotIn("allocate-ids", source)
        self.assertNotIn("master_catalog_barcodes", source)


if __name__ == "__main__":
    unittest.main()
