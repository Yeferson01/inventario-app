from __future__ import annotations

import csv
import gzip
import io
import json
import socket
import sqlite3
import sys
import tempfile
import unittest
import uuid
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock


TOOL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL_DIR))

import catalog_tool  # noqa: E402
from acquisition import candidate_tool  # noqa: E402
from resolution import candidate_resolution as tool  # noqa: E402


class CandidateResolutionTest(unittest.TestCase):
    OFF_HEADERS = [*tool.REQUIRED_OFF_HEADERS, "large_text", "creator"]

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.candidates = self.root / "candidates.csv"
        self.off_input = self.root / "products.csv.gz"
        self.output = self.root / "resolution.csv"
        self.metrics = self.root / "metrics.json"

    @staticmethod
    def _candidate(
        barcode: str = "4006381333931",
        barcode_type: str = "ean13",
        **overrides: str,
    ) -> dict[str, str]:
        row = {
            "raw_barcode": barcode,
            "barcode": barcode,
            "barcode_type": barcode_type,
            "name_if_known": "Candidate name",
            "brand_if_known": "Candidate brand",
            "source": "open_dataset",
            "source_channel": "open_food_facts",
            "source_reference": "open-food-facts:snapshot:test",
            "source_record_id": "",
            "retrieved_at": "2026-09-08T12:34:56-05:00",
            "rights_class": "open_dataset_odbl_share_alike",
            "rights_reference": "odbl:test",
            "can_persist_candidate": "true",
            "candidate_confidence": "medium",
            "colombia_evidence_type": "other_documented",
            "colombia_evidence_count": "1",
            "source_content_sha256": "a" * 64,
            "notes": "",
        }
        row.update(overrides)
        return row

    @classmethod
    def _off_row(cls, code: str = "4006381333931", **overrides: str) -> dict[str, str]:
        row = {
            "code": code,
            "product_name": "OFF Product",
            "brands": "OFF Brand",
            "categories_tags": "en:foods,en:snacks",
            "main_category": "en:snacks",
            "quantity": "6 x 330 ml",
            "last_modified_t": "1788800000",
            "large_text": "",
            "creator": "must-not-appear",
        }
        row.update(overrides)
        return row

    def _write_candidates(
        self,
        rows: list[dict[str, str]],
        headers: list[str] | None = None,
    ) -> None:
        with self.candidates.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(
                handle,
                fieldnames=headers or candidate_tool.CANDIDATE_HEADERS,
                lineterminator="\n",
                extrasaction="ignore",
            )
            writer.writeheader()
            writer.writerows(rows)

    def _write_off(
        self,
        rows: list[dict[str, str]],
        headers: list[str] | None = None,
        *,
        bom: bool = False,
    ) -> None:
        with gzip.open(self.off_input, "wt", encoding="utf-8", newline="") as handle:
            if bom:
                handle.write("\ufeff")
            writer = csv.DictWriter(
                handle,
                fieldnames=headers or self.OFF_HEADERS,
                delimiter="\t",
                lineterminator="\n",
                extrasaction="ignore",
            )
            writer.writeheader()
            writer.writerows(rows)

    def _write_raw_off_lines(self, lines: list[str]) -> None:
        with gzip.open(self.off_input, "wt", encoding="utf-8", newline="") as handle:
            handle.write("\t".join(self.OFF_HEADERS) + "\n")
            handle.writelines(lines)

    def _plain_off_line(self, row: dict[str, str]) -> str:
        return "\t".join(row[header] for header in self.OFF_HEADERS) + "\n"

    def _build(
        self,
        candidates: list[dict[str, str]] | None = None,
        off_rows: list[dict[str, str]] | None = None,
        *,
        off_headers: list[str] | None = None,
        bom: bool = False,
    ) -> dict[str, object]:
        self._write_candidates(candidates or [self._candidate()])
        self._write_off(off_rows or [self._off_row()], off_headers, bom=bom)
        return tool.build_snapshot(
            candidates_path=self.candidates,
            off_input_path=self.off_input,
            output_path=self.output,
            metrics_path=self.metrics,
        )

    @staticmethod
    def _csv_rows(path: Path) -> list[dict[str, str]]:
        with path.open("r", encoding="utf-8", newline="") as handle:
            return list(csv.DictReader(handle))

    def _resolution_rows(self) -> list[dict[str, str]]:
        return self._csv_rows(self.output)

    def test_01_valid_a1_candidate_matches_and_preserves_identity(self) -> None:
        metrics = self._build(bom=True)
        row = self._resolution_rows()[0]
        self.assertEqual(row["barcode"], "4006381333931")
        self.assertEqual(row["barcode_type"], "ean13")
        self.assertEqual(row["source_match_status"], "matched")
        self.assertEqual(metrics["candidates_total"], 1)
        self.assertEqual(metrics["candidates_valid"], 1)
        self.assertEqual(metrics["matched_candidates"], 1)
        self.assertEqual(metrics["missing_candidates"], 0)

    def test_02_invalid_a1_candidate_blocks(self) -> None:
        self._write_candidates([self._candidate(can_persist_candidate="false")])
        self._write_off([self._off_row()])
        with self.assertRaisesRegex(tool.ResolutionValidationError, "A1.1"):
            tool.build_snapshot(
                candidates_path=self.candidates,
                off_input_path=self.off_input,
                output_path=self.output,
                metrics_path=self.metrics,
            )
        self.assertFalse(self.output.exists())

    def test_03_non_off_candidate_channel_blocks(self) -> None:
        candidate = self._candidate(source_channel="open_prices")
        self._write_candidates([candidate])
        self._write_off([self._off_row()])
        with self.assertRaisesRegex(tool.ResolutionValidationError, "not an Open Food Facts"):
            tool.build_snapshot(
                candidates_path=self.candidates,
                off_input_path=self.off_input,
                output_path=self.output,
                metrics_path=self.metrics,
            )

    def test_04_duplicate_candidate_barcode_blocks(self) -> None:
        self._write_candidates([self._candidate(), self._candidate()])
        self._write_off([self._off_row()])
        with self.assertRaisesRegex(tool.ResolutionValidationError, "A1.1"):
            tool.build_snapshot(
                candidates_path=self.candidates,
                off_input_path=self.off_input,
                output_path=self.output,
                metrics_path=self.metrics,
            )

    def test_05_each_required_off_header_is_enforced(self) -> None:
        for missing_header in tool.REQUIRED_OFF_HEADERS:
            with self.subTest(missing_header=missing_header):
                headers = [header for header in self.OFF_HEADERS if header != missing_header]
                self._write_candidates([self._candidate()])
                self._write_off([self._off_row()], headers)
                with self.assertRaisesRegex(tool.ResolutionToolError, missing_header):
                    tool.build_snapshot(
                        candidates_path=self.candidates,
                        off_input_path=self.off_input,
                        output_path=self.output,
                        metrics_path=self.metrics,
                    )

    def test_06_ean8_leading_zero_and_final_order_are_preserved(self) -> None:
        candidates = [
            self._candidate(),
            self._candidate(
                "01234565", "ean8", source_content_sha256="b" * 64, raw_barcode="01234565"
            ),
        ]
        off_rows = [self._off_row(), self._off_row("01234565")]
        metrics = self._build(candidates, off_rows)
        rows = self._resolution_rows()
        self.assertEqual([row["barcode"] for row in rows], ["01234565", "4006381333931"])
        self.assertEqual(rows[0]["barcode_type"], "ean8")
        self.assertEqual(metrics["ean8_count"], 1)
        self.assertEqual(metrics["ean13_count"], 1)

    def test_07_factual_fields_and_provenance_are_preserved(self) -> None:
        candidate = self._candidate(
            name_if_known=" Candidate hint ",
            brand_if_known="Candidate brand hint",
            source_reference="snapshot:exact",
            source_content_sha256="C" * 64,
            retrieved_at="2026-09-08T17:34:56Z",
            rights_reference="odbl:exact",
        )
        off = self._off_row(
            product_name=" OFF name ",
            brands=" OFF brand ",
            categories_tags=" en:foods,en:biscuits ",
            main_category=" en:biscuits ",
            quantity=" 500 g ",
            last_modified_t=" 1788800123 ",
        )
        self._build([candidate], [off])
        row = self._resolution_rows()[0]
        self.assertEqual(row["candidate_name_if_known"], " Candidate hint ")
        self.assertEqual(row["candidate_brand_if_known"], "Candidate brand hint")
        self.assertEqual(row["off_product_name"], "OFF name")
        self.assertEqual(row["off_brands"], "OFF brand")
        self.assertEqual(row["off_categories_tags"], "en:foods,en:biscuits")
        self.assertEqual(row["off_main_category"], "en:biscuits")
        self.assertEqual(row["off_quantity"], "500 g")
        self.assertEqual(row["off_last_modified_t"], "1788800123")
        self.assertEqual(row["candidate_source_reference"], "snapshot:exact")
        self.assertEqual(row["candidate_source_content_sha256"], "C" * 64)
        self.assertEqual(row["retrieved_at"], "2026-09-08T17:34:56Z")
        self.assertEqual(row["rights_class"], "open_dataset_odbl_share_alike")
        self.assertEqual(row["rights_reference"], "odbl:exact")

    def test_08_available_and_missing_statuses(self) -> None:
        candidates = [
            self._candidate(),
            self._candidate(
                "01234565", "ean8", source_content_sha256="b" * 64, raw_barcode="01234565"
            ),
        ]
        off_rows = [
            self._off_row(),
            self._off_row(
                "01234565",
                product_name="",
                brands="",
                categories_tags="",
                main_category="",
                quantity="",
            ),
        ]
        metrics = self._build(candidates, off_rows)
        rows = {row["barcode"]: row for row in self._resolution_rows()}
        for field in ("name_status", "brand_status", "category_status", "quantity_status"):
            self.assertEqual(rows["4006381333931"][field], "available")
            self.assertEqual(rows["01234565"][field], "missing")
        self.assertEqual(metrics["with_name"], 1)
        self.assertEqual(metrics["without_name"], 1)
        self.assertEqual(metrics["with_brand"], 1)
        self.assertEqual(metrics["without_brand"], 1)
        self.assertEqual(metrics["with_category"], 1)
        self.assertEqual(metrics["without_category"], 1)
        self.assertEqual(metrics["with_quantity"], 1)
        self.assertEqual(metrics["without_quantity"], 1)

    def test_09_candidate_and_off_values_are_not_reconciled(self) -> None:
        self._build(
            [self._candidate(name_if_known="Candidate value", brand_if_known="Candidate brand")],
            [self._off_row(product_name="Different OFF value", brands="Different OFF brand")],
        )
        row = self._resolution_rows()[0]
        self.assertEqual(row["candidate_name_if_known"], "Candidate value")
        self.assertEqual(row["off_product_name"], "Different OFF value")
        self.assertEqual(row["candidate_brand_if_known"], "Candidate brand")
        self.assertEqual(row["off_brands"], "Different OFF brand")
        self.assertEqual(row["name_status"], "available")
        self.assertEqual(row["brand_status"], "available")

    def test_10_identical_off_rows_aggregate_without_duplicate_resolution(self) -> None:
        off = self._off_row()
        metrics = self._build(off_rows=[off, dict(off)])
        rows = self._resolution_rows()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["off_source_row_count"], "2")
        self.assertEqual(metrics["off_candidate_rows_matched"], 2)
        self.assertEqual(metrics["duplicate_off_rows"], 1)

    def test_11_all_supported_conflicts_are_explicit_and_blank(self) -> None:
        rows = [
            self._off_row(
                product_name="Name A",
                brands="Brand A",
                categories_tags="en:category-a",
                main_category="en:category-a",
                quantity="500 g",
            ),
            self._off_row(
                product_name="Name B",
                brands="Brand B",
                categories_tags="en:category-b",
                main_category="en:category-b",
                quantity="1 kg",
            ),
        ]
        metrics = self._build(off_rows=rows)
        row = self._resolution_rows()[0]
        self.assertEqual(row["off_product_name"], "")
        self.assertEqual(row["off_brands"], "")
        self.assertEqual(row["off_categories_tags"], "")
        self.assertEqual(row["off_main_category"], "")
        self.assertEqual(row["off_quantity"], "")
        self.assertEqual(row["name_status"], "conflict")
        self.assertEqual(row["brand_status"], "conflict")
        self.assertEqual(row["category_status"], "conflict")
        self.assertEqual(row["quantity_status"], "conflict")
        self.assertEqual(metrics["name_conflicts"], 1)
        self.assertEqual(metrics["brand_conflicts"], 1)
        self.assertEqual(metrics["category_conflicts"], 1)
        self.assertEqual(metrics["quantity_conflicts"], 1)

    def test_12_exterior_whitespace_converges_without_inventing_value(self) -> None:
        rows = [self._off_row(), self._off_row(product_name=" OFF Product ", brands=" OFF Brand ")]
        self._build(off_rows=rows)
        row = self._resolution_rows()[0]
        self.assertEqual(row["off_product_name"], "OFF Product")
        self.assertEqual(row["off_brands"], "OFF Brand")
        self.assertEqual(row["name_status"], "available")
        self.assertEqual(row["brand_status"], "available")

    def test_13_category_available_when_only_one_structured_field_exists(self) -> None:
        self._build(off_rows=[self._off_row(categories_tags="", main_category="en:snacks")])
        row = self._resolution_rows()[0]
        self.assertEqual(row["off_categories_tags"], "")
        self.assertEqual(row["off_main_category"], "en:snacks")
        self.assertEqual(row["category_status"], "available")

    def test_14_category_conflict_preserves_convergent_main_category(self) -> None:
        self._build(
            off_rows=[
                self._off_row(categories_tags="en:category-a", main_category="en:shared"),
                self._off_row(categories_tags="en:category-b", main_category=" en:shared "),
            ]
        )
        row = self._resolution_rows()[0]
        self.assertEqual(row["off_categories_tags"], "")
        self.assertEqual(row["off_main_category"], "en:shared")
        self.assertEqual(row["category_status"], "conflict")

    def test_15_hashes_are_deterministic_and_ignore_off_row_order(self) -> None:
        rows = [
            self._off_row(last_modified_t="1"),
            self._off_row(last_modified_t="1", large_text="second evidence"),
        ]
        self._build(off_rows=rows)
        first_bytes = self.output.read_bytes()
        first = self._resolution_rows()[0]
        self._build(off_rows=list(reversed(rows)))
        second = self._resolution_rows()[0]
        self.assertEqual(self.output.read_bytes(), first_bytes)
        self.assertEqual(second["off_source_content_sha256"], first["off_source_content_sha256"])
        self.assertEqual(second["resolution_record_sha256"], first["resolution_record_sha256"])

    def test_16_source_and_resolution_hashes_follow_the_contract(self) -> None:
        off = self._off_row()
        self._build(off_rows=[off])
        row = self._resolution_rows()[0]
        source_hash = catalog_tool.record_hash(off)
        expected_off_hash = catalog_tool.record_hash(
            {"barcode": off["code"], "supporting_source_hashes": [source_hash]}
        )
        self.assertEqual(row["off_source_content_sha256"], expected_off_hash)
        expected_resolution_hash = catalog_tool.record_hash(
            {
                header: row[header]
                for header in tool.RESOLUTION_HEADERS
                if header != "resolution_record_sha256"
            }
        )
        self.assertEqual(row["resolution_record_sha256"], expected_resolution_hash)

    def test_17_factual_change_changes_both_hashes(self) -> None:
        self._build(off_rows=[self._off_row(quantity="500 g")])
        first = self._resolution_rows()[0]
        self._build(off_rows=[self._off_row(quantity="1 kg")])
        second = self._resolution_rows()[0]
        self.assertNotEqual(first["off_source_content_sha256"], second["off_source_content_sha256"])
        self.assertNotEqual(first["resolution_record_sha256"], second["resolution_record_sha256"])

    def test_18_missing_candidate_blocks_publication(self) -> None:
        self.output.write_text("existing-safe-output\n", encoding="utf-8")
        candidates = [
            self._candidate(),
            self._candidate(
                "01234565", "ean8", source_content_sha256="b" * 64, raw_barcode="01234565"
            ),
        ]
        self._write_candidates(candidates)
        self._write_off([self._off_row()])
        with self.assertRaisesRegex(tool.ResolutionValidationError, "missing 1"):
            tool.build_snapshot(
                candidates_path=self.candidates,
                off_input_path=self.off_input,
                output_path=self.output,
                metrics_path=self.metrics,
            )
        self.assertEqual(self.output.read_text(encoding="utf-8"), "existing-safe-output\n")
        self.assertFalse(self.metrics.exists())

    def test_19_output_contract_has_one_row_per_candidate(self) -> None:
        candidates = [
            self._candidate(),
            self._candidate(
                "01234565", "ean8", source_content_sha256="b" * 64, raw_barcode="01234565"
            ),
        ]
        self._build(candidates, [self._off_row(), self._off_row("01234565")])
        with self.output.open("r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            self.assertEqual(reader.fieldnames, tool.RESOLUTION_HEADERS)
            rows = list(reader)
        self.assertEqual(len(rows), 2)
        self.assertEqual(len({row["barcode"] for row in rows}), 2)

    def test_20_output_is_atomic_when_validation_fails(self) -> None:
        self.output.write_text("existing-safe-output\n", encoding="utf-8")
        self._write_candidates([self._candidate()])
        self._write_off([self._off_row()])
        with mock.patch.object(
            tool,
            "_validate_resolution_output",
            side_effect=tool.ResolutionValidationError("forced"),
        ):
            with self.assertRaises(tool.ResolutionValidationError):
                tool.build_snapshot(
                    candidates_path=self.candidates,
                    off_input_path=self.off_input,
                    output_path=self.output,
                    metrics_path=self.metrics,
                )
        self.assertEqual(self.output.read_text(encoding="utf-8"), "existing-safe-output\n")
        self.assertFalse(self.metrics.exists())
        self.assertEqual(list(self.root.glob("*.tmp")), [])

    def test_21_field_larger_than_default_csv_limit_is_supported(self) -> None:
        large_text = "x" * 200_000
        metrics = self._build(off_rows=[self._off_row(large_text=large_text)])
        self.assertGreater(tool.CSV_FIELD_SIZE_LIMIT, 131_072)
        self.assertEqual(metrics["matched_candidates"], 1)
        self.assertEqual(len(self._resolution_rows()), 1)

    def test_22_malformed_off_row_fails_closed(self) -> None:
        self._write_candidates([self._candidate()])
        with gzip.open(self.off_input, "wt", encoding="utf-8", newline="") as handle:
            handle.write("\t".join(self.OFF_HEADERS) + "\n")
            handle.write("4006381333931\ttoo-few-fields\n")
        with self.assertRaisesRegex(tool.ResolutionValidationError, "missing 1 candidate"):
            tool.build_snapshot(
                candidates_path=self.candidates,
                off_input_path=self.off_input,
                output_path=self.output,
                metrics_path=self.metrics,
            )

    def test_23_no_network_database_or_uuid_access(self) -> None:
        with (
            mock.patch.object(socket, "socket", side_effect=AssertionError("network used")),
            mock.patch.object(sqlite3, "connect", side_effect=AssertionError("database used")),
            mock.patch.object(uuid, "uuid4", side_effect=AssertionError("uuid used")),
        ):
            metrics = self._build()
        self.assertFalse(metrics["network_access"])
        self.assertFalse(metrics["database_access"])
        self.assertFalse(metrics["uuid_generation"])

    def test_24_cli_build_prints_human_report(self) -> None:
        self._write_candidates([self._candidate()])
        self._write_off([self._off_row()])
        output = io.StringIO()
        with redirect_stdout(output):
            exit_code = tool.main(
                [
                    "build",
                    "--candidates",
                    str(self.candidates),
                    "--off-input",
                    str(self.off_input),
                    "--output",
                    str(self.output),
                    "--metrics",
                    str(self.metrics),
                ]
            )
        self.assertEqual(exit_code, 0)
        self.assertIn("Candidate Resolution Snapshot: SUCCESS", output.getvalue())
        self.assertIn("Network access: none", output.getvalue())
        parsed_metrics = json.loads(self.metrics.read_text(encoding="utf-8"))
        self.assertEqual(parsed_metrics["matched_candidates"], 1)

    def test_25_unrelated_malformed_row_is_skipped_and_later_candidate_resolves(self) -> None:
        self._write_candidates([self._candidate()])
        malformed = (
            '9999999999999\t"must-not-be-used\n'
            'continued" trailing\tBad Brand\ten:bad\ten:bad\t999 g\t1\t'
            "\tbad-creator\textra-field\n"
        )
        strict_reader = csv.reader(
            io.StringIO("\t".join(self.OFF_HEADERS) + "\n" + malformed),
            delimiter="\t",
            strict=True,
        )
        next(strict_reader)
        with self.assertRaises(csv.Error):
            next(strict_reader)
        self.assertGreater(strict_reader.line_num, 2)
        self._write_raw_off_lines([malformed, self._plain_off_line(self._off_row())])

        metrics = tool.build_snapshot(
            candidates_path=self.candidates,
            off_input_path=self.off_input,
            output_path=self.output,
            metrics_path=self.metrics,
        )

        self.assertEqual(metrics["off_malformed_csv_rows"], 1)
        self.assertEqual(metrics["off_rows_scanned"], 2)
        self.assertEqual(metrics["matched_candidates"], 1)
        row = self._resolution_rows()[0]
        self.assertEqual(row["off_product_name"], "OFF Product")
        self.assertEqual(row["off_brands"], "OFF Brand")
        self.assertFalse(any("must-not-be-used" in value for value in row.values()))
        self.assertIn("Malformed OFF CSV rows skipped: 1", tool.human_report(metrics))

    def test_26_malformed_only_candidate_is_missing_without_partial_publication(self) -> None:
        self._write_candidates([self._candidate()])
        malformed = (
            '4006381333931\t"must-not-be-used\n'
            'continued" trailing\tBad Brand\ten:bad\ten:bad\t999 g\t1\t'
            "\tbad-creator\textra-field\n"
        )
        self._write_raw_off_lines([malformed])
        self.output.write_text("existing-safe-output\n", encoding="utf-8")
        self.metrics.write_text("existing-safe-metrics\n", encoding="utf-8")

        with self.assertRaisesRegex(tool.ResolutionValidationError, "missing 1 candidate"):
            tool.build_snapshot(
                candidates_path=self.candidates,
                off_input_path=self.off_input,
                output_path=self.output,
                metrics_path=self.metrics,
            )

        self.assertEqual(self.output.read_text(encoding="utf-8"), "existing-safe-output\n")
        self.assertEqual(self.metrics.read_text(encoding="utf-8"), "existing-safe-metrics\n")

    def test_27_malformed_row_recovery_is_deterministic(self) -> None:
        self._write_candidates([self._candidate()])
        malformed = (
            '9999999999999\t"must-not-be-used\n'
            'continued" trailing\tBad Brand\ten:bad\ten:bad\t999 g\t1\t'
            "\tbad-creator\textra-field\n"
        )
        self._write_raw_off_lines([malformed, self._plain_off_line(self._off_row())])
        second_output = self.root / "resolution-second.csv"
        second_metrics = self.root / "metrics-second.json"

        tool.build_snapshot(
            candidates_path=self.candidates,
            off_input_path=self.off_input,
            output_path=self.output,
            metrics_path=self.metrics,
        )
        tool.build_snapshot(
            candidates_path=self.candidates,
            off_input_path=self.off_input,
            output_path=second_output,
            metrics_path=second_metrics,
        )

        self.assertEqual(self.output.read_bytes(), second_output.read_bytes())
        self.assertEqual(self.metrics.read_bytes(), second_metrics.read_bytes())

    def test_28_valid_multiline_record_is_not_malformed(self) -> None:
        multiline_name = "OFF Product\nSecond physical line"
        metrics = self._build(off_rows=[self._off_row(product_name=multiline_name)])

        row = self._resolution_rows()[0]
        self.assertEqual(row["off_product_name"], multiline_name)
        self.assertEqual(metrics["off_rows_scanned"], 1)
        self.assertEqual(metrics["off_malformed_csv_rows"], 0)

    def test_29_tolerant_correct_width_record_is_processed(self) -> None:
        self._write_candidates([self._candidate()])
        recovered = (
            '4006381333931\t"OFF Product\n'
            'Second physical line" trailing\tOFF Brand\ten:foods,en:snacks\t'
            "en:snacks\t6 x 330 ml\t1788800000\t\tmust-not-appear\n"
        )
        strict_reader = csv.reader(
            io.StringIO("\t".join(self.OFF_HEADERS) + "\n" + recovered),
            delimiter="\t",
            strict=True,
        )
        next(strict_reader)
        with self.assertRaises(csv.Error):
            next(strict_reader)
        self._write_raw_off_lines([recovered])

        metrics = tool.build_snapshot(
            candidates_path=self.candidates,
            off_input_path=self.off_input,
            output_path=self.output,
            metrics_path=self.metrics,
        )

        row = self._resolution_rows()[0]
        self.assertEqual(
            row["off_product_name"],
            "OFF Product\nSecond physical line trailing",
        )
        self.assertEqual(metrics["off_rows_scanned"], 1)
        self.assertEqual(metrics["off_malformed_csv_rows"], 0)


if __name__ == "__main__":
    unittest.main()
