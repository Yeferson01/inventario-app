from __future__ import annotations

import csv
import gzip
import hashlib
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

from acquisition import candidate_tool  # noqa: E402
from acquisition import open_food_facts_bulk as tool  # noqa: E402


class OpenFoodFactsBulkTest(unittest.TestCase):
    SOURCE_REFERENCE = "open-food-facts:snapshot:2026-09-08"
    RIGHTS_REFERENCE = "odbl:open-food-facts:2026-09-08"
    RETRIEVED_AT = "2026-09-08T12:34:56-05:00"
    HEADERS = [
        "code",
        "countries_tags",
        "product_name",
        "brands",
        "categories_tags",
        "last_modified_t",
        "creator",
        "ingredients_text",
    ]

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.input = self.root / "open-food-facts.csv.gz"
        self.candidates = self.root / "candidates.csv"
        self.evidence = self.root / "evidence.csv"
        self.rejects = self.root / "rejects.csv"
        self.metrics = self.root / "metrics.json"

    @classmethod
    def _row(cls, code: str = "4006381333931", **overrides: str) -> dict[str, str]:
        row = {
            "code": code,
            "countries_tags": "en:colombia",
            "product_name": "Producto",
            "brands": "Marca",
            "categories_tags": "en:foods",
            "last_modified_t": "1788800000",
            "creator": "must-not-leak",
            "ingredients_text": "must-not-leak",
        }
        row.update(overrides)
        return row

    @staticmethod
    def _write_dump(
        path: Path,
        headers: list[str],
        rows: list[dict[str, str]],
        *,
        delimiter: str = "\t",
        bom: bool = False,
    ) -> None:
        with gzip.open(path, "wt", encoding="utf-8", newline="") as handle:
            if bom:
                handle.write("\ufeff")
            writer = csv.DictWriter(
                handle,
                fieldnames=headers,
                delimiter=delimiter,
                lineterminator="\n",
                extrasaction="ignore",
            )
            writer.writeheader()
            writer.writerows(rows)

    def _extract(
        self,
        rows: list[dict[str, str]] | None = None,
        *,
        headers: list[str] | None = None,
        delimiter: str = "\t",
        bom: bool = False,
        countries_column: str | None = None,
        max_candidates: int | None = None,
    ) -> dict[str, object]:
        self._write_dump(
            self.input,
            headers or self.HEADERS,
            rows if rows is not None else [self._row()],
            delimiter=delimiter,
            bom=bom,
        )
        return tool.extract(
            input_path=self.input,
            candidates_path=self.candidates,
            evidence_path=self.evidence,
            rejects_path=self.rejects,
            metrics_path=self.metrics,
            source_reference=self.SOURCE_REFERENCE,
            rights_reference=self.RIGHTS_REFERENCE,
            retrieved_at=self.RETRIEVED_AT,
            countries_column=countries_column,
            max_candidates=max_candidates,
        )

    @staticmethod
    def _csv_rows(path: Path) -> list[dict[str, str]]:
        with path.open("r", encoding="utf-8", newline="") as handle:
            return list(csv.DictReader(handle))

    def _candidate_rows(self) -> list[dict[str, str]]:
        return self._csv_rows(self.candidates)

    def _reject_codes(self) -> list[str]:
        return [row["reason_code"] for row in self._csv_rows(self.rejects)]

    def test_01_realistic_tab_header_and_bom_are_detected(self) -> None:
        metrics = self._extract(bom=True)
        self.assertEqual(metrics["input_delimiter"], "tab")
        self.assertEqual(metrics["countries_column_used"], "countries_tags")
        self.assertEqual(metrics["accepted_candidates"], 1)

    def test_02_comma_and_semicolon_headers_are_detected(self) -> None:
        self.assertEqual(self._extract(delimiter=",")["input_delimiter"], "comma")
        self.assertEqual(self._extract(delimiter=";")["input_delimiter"], "semicolon")

    def test_03_missing_code_fails_before_outputs(self) -> None:
        with self.assertRaisesRegex(tool.OpenFoodFactsBulkError, "missing required column: code"):
            self._extract(headers=["countries_tags", "product_name"])
        self.assertFalse(self.candidates.exists())

    def test_04_missing_country_column_requires_explicit_override(self) -> None:
        headers = ["code", "market_tags", "product_name"]
        row = {"code": "4006381333931", "market_tags": "en:colombia", "product_name": "P"}
        with self.assertRaisesRegex(tool.OpenFoodFactsBulkError, "--countries-column"):
            self._extract([row], headers=headers)
        metrics = self._extract([row], headers=headers, countries_column="market_tags")
        self.assertEqual(metrics["countries_column_used"], "market_tags")
        self.assertEqual(metrics["accepted_candidates"], 1)

    def test_05_countries_tags_has_priority_over_override(self) -> None:
        headers = ["code", "countries_tags", "market_tags"]
        row = {
            "code": "4006381333931",
            "countries_tags": "en:france",
            "market_tags": "en:colombia",
        }
        metrics = self._extract([row], headers=headers, countries_column="market_tags")
        self.assertEqual(metrics["countries_column_used"], "countries_tags")
        self.assertEqual(metrics["accepted_candidates"], 0)

    def test_06_exact_colombia_tag_is_case_insensitive(self) -> None:
        rows = [
            self._row("4006381333931", countries_tags=" en:colombia ,en:france "),
            self._row("96385074", countries_tags="EN:COLOMBIA"),
        ]
        metrics = self._extract(rows)
        self.assertEqual(metrics["rows_colombia"], 2)
        self.assertEqual(len(self._candidate_rows()), 2)

    def test_07_other_country_and_colombia_substring_do_not_participate(self) -> None:
        metrics = self._extract(
            [
                self._row("4006381333931", countries_tags="en:france"),
                self._row("96385074", countries_tags="en:colombian-products"),
            ]
        )
        self.assertEqual(metrics["rows_not_colombia"], 2)
        self.assertEqual(metrics["accepted_candidates"], 0)
        self.assertEqual(self._reject_codes(), [])

    def test_08_invalid_alternative_country_format_is_rejected(self) -> None:
        headers = ["code", "market_tags"]
        metrics = self._extract(
            [{"code": "4006381333931", "market_tags": "Colombia"}],
            headers=headers,
            countries_column="market_tags",
        )
        self.assertEqual(metrics["invalid_country_fields"], 1)
        self.assertEqual(self._reject_codes(), ["invalid_country_field"])

    def test_09_all_supported_gtin_lengths_are_accepted(self) -> None:
        rows = [
            self._row("96385074"),
            self._row("036000291452"),
            self._row("4006381333931"),
            self._row("10012345000017"),
        ]
        self._extract(rows)
        self.assertEqual(
            [(row["barcode"], row["barcode_type"]) for row in self._candidate_rows()],
            [
                ("036000291452", "upc"),
                ("10012345000017", "gtin"),
                ("4006381333931", "ean13"),
                ("96385074", "ean8"),
            ],
        )

    def test_10_leading_zero_and_exterior_whitespace_are_preserved(self) -> None:
        self._extract([self._row(" 036000291452 ")])
        candidate = self._candidate_rows()[0]
        self.assertEqual(candidate["raw_barcode"], " 036000291452 ")
        self.assertEqual(candidate["barcode"], "036000291452")

    def test_11_checksum_scientific_notation_and_length_fail(self) -> None:
        metrics = self._extract(
            [
                self._row("4006381333932"),
                self._row("4.006381333931E+12"),
                self._row("123456789"),
            ]
        )
        self.assertEqual(metrics["invalid_checksum"], 1)
        self.assertEqual(metrics["scientific_notation"], 1)
        self.assertEqual(metrics["unsupported_barcode"], 1)
        self.assertCountEqual(
            self._reject_codes(),
            ["invalid_barcode", "invalid_barcode", "unsupported_barcode_length"],
        )

    def test_12_generated_off_identifier_is_excluded(self) -> None:
        metrics = self._extract([self._row("2000000152012")])
        self.assertEqual(metrics["generated_or_internal_identifier"], 1)
        self.assertEqual(self._reject_codes(), ["generated_or_internal_identifier"])
        self.assertEqual(self._candidate_rows(), [])

    def test_13_empty_code_is_rejected(self) -> None:
        metrics = self._extract([self._row("")])
        self.assertEqual(metrics["missing_code"], 1)
        self.assertEqual(self._reject_codes(), ["empty_code"])

    def test_14_name_brand_and_empty_hints_are_supported(self) -> None:
        self._extract(
            [
                self._row("4006381333931", product_name=" Café   Uno ", brands="Marca Uno"),
                self._row("96385074", product_name="", brands=""),
            ]
        )
        rows = {row["barcode"]: row for row in self._candidate_rows()}
        self.assertEqual(rows["4006381333931"]["name_if_known"], "Café Uno")
        self.assertEqual(rows["4006381333931"]["brand_if_known"], "Marca Uno")
        self.assertEqual(rows["96385074"]["name_if_known"], "")
        self.assertEqual(rows["96385074"]["brand_if_known"], "")

    def test_15_duplicate_gtin_converges_name_and_brand(self) -> None:
        metrics = self._extract(
            [
                self._row(product_name=" Café   Uno ", brands=" MARCA ", last_modified_t="1"),
                self._row(product_name="Café Uno", brands="marca", last_modified_t="2"),
            ]
        )
        self.assertEqual(len(self._candidate_rows()), 1)
        candidate = self._candidate_rows()[0]
        self.assertEqual(candidate["name_if_known"], "Café Uno")
        self.assertEqual(candidate["brand_if_known"], "MARCA")
        self.assertEqual(metrics["duplicate_gtin_rows"], 1)
        self.assertEqual(len(self._csv_rows(self.evidence)), 2)
        self.assertEqual(candidate["colombia_evidence_count"], "1")

    def test_16_name_and_brand_conflicts_are_not_chosen(self) -> None:
        metrics = self._extract(
            [
                self._row(product_name="Producto A", brands="Marca A", last_modified_t="1"),
                self._row(product_name="Producto B", brands="Marca B", last_modified_t="2"),
            ]
        )
        candidate = self._candidate_rows()[0]
        self.assertEqual(candidate["name_if_known"], "")
        self.assertEqual(candidate["brand_if_known"], "")
        self.assertEqual(candidate["notes"], "name_conflict;brand_conflict")
        self.assertEqual(metrics["candidate_name_conflicts"], 1)
        self.assertEqual(metrics["candidate_brand_conflicts"], 1)
        self.assertTrue(all(row["name_conflict"] == "true" for row in self._csv_rows(self.evidence)))
        self.assertTrue(all(row["brand_conflict"] == "true" for row in self._csv_rows(self.evidence)))

    def test_17_identical_source_row_is_rejected_once(self) -> None:
        row = self._row()
        metrics = self._extract([row, dict(row)])
        self.assertEqual(metrics["valid_gtin_rows"], 2)
        self.assertEqual(metrics["duplicate_source_rows"], 1)
        self.assertEqual(metrics["duplicate_gtin_rows"], 1)
        self.assertEqual(len(self._csv_rows(self.evidence)), 1)
        self.assertEqual(self._reject_codes(), ["duplicate_source_row"])

    def test_18_aggregate_hash_ignores_physical_row_order(self) -> None:
        rows = [
            self._row(product_name="Producto", last_modified_t="1"),
            self._row(product_name="Producto", last_modified_t="2"),
        ]
        self._extract(rows)
        first_candidate = self.candidates.read_bytes()
        first_hash = self._candidate_rows()[0]["source_content_sha256"]
        self._extract(list(reversed(rows)))
        self.assertEqual(self.candidates.read_bytes(), first_candidate)
        self.assertEqual(self._candidate_rows()[0]["source_content_sha256"], first_hash)

    def test_19_candidate_uses_exact_a11_contract_and_passes_validation(self) -> None:
        self._extract()
        candidate = self._candidate_rows()[0]
        self.assertEqual(list(candidate), candidate_tool.CANDIDATE_HEADERS)
        self.assertEqual(candidate["source"], "open_dataset")
        self.assertEqual(candidate["source_channel"], "open_food_facts")
        self.assertEqual(candidate["rights_class"], "open_dataset_odbl_share_alike")
        self.assertEqual(candidate["can_persist_candidate"], "true")
        self.assertEqual(candidate["candidate_confidence"], "medium")
        self.assertEqual(candidate["colombia_evidence_type"], "other_documented")
        self.assertEqual(candidate["colombia_evidence_count"], "1")
        report = candidate_tool.validate_candidates(input_path=self.candidates)
        self.assertTrue(report["valid"], report["blocking_errors"])

    def test_20_max_candidates_ranks_name_then_brand_then_evidence(self) -> None:
        rows = [
            self._row("4006381333931", product_name="Nombre", brands="", last_modified_t="1"),
            self._row("96385074", product_name="", brands="Marca", last_modified_t="1"),
            self._row("96385074", product_name="", brands="Marca", last_modified_t="2"),
            self._row("96385074", product_name="", brands="Marca", last_modified_t="3"),
            self._row("036000291452", product_name="Nombre", brands="Marca", last_modified_t="1"),
            self._row(
                "10012345000017", product_name="Nombre", brands="Marca", last_modified_t="1"
            ),
            self._row(
                "10012345000017", product_name="Nombre", brands="Marca", last_modified_t="2"
            ),
        ]
        metrics = self._extract(rows, max_candidates=3)
        self.assertEqual(
            [row["barcode"] for row in self._candidate_rows()],
            ["10012345000017", "036000291452", "4006381333931"],
        )
        self.assertEqual(metrics["unique_valid_gtins"], 4)
        self.assertEqual(metrics["accepted_candidates"], 3)
        self.assertTrue(metrics["max_candidates_applied"])

    def test_21_input_gzip_is_not_modified_and_evidence_is_minimal(self) -> None:
        self._write_dump(self.input, self.HEADERS, [self._row()])
        before = hashlib.sha256(self.input.read_bytes()).hexdigest()
        tool.extract(
            input_path=self.input,
            candidates_path=self.candidates,
            evidence_path=self.evidence,
            rejects_path=self.rejects,
            metrics_path=self.metrics,
            source_reference=self.SOURCE_REFERENCE,
            rights_reference=self.RIGHTS_REFERENCE,
            retrieved_at=self.RETRIEVED_AT,
        )
        self.assertEqual(hashlib.sha256(self.input.read_bytes()).hexdigest(), before)
        evidence = self._csv_rows(self.evidence)[0]
        self.assertNotIn("creator", evidence)
        self.assertNotIn("ingredients_text", evidence)
        self.assertNotIn("categories_tags", evidence)

    def test_22_malformed_csv_row_and_excluded_category_are_rejected(self) -> None:
        with gzip.open(self.input, "wt", encoding="utf-8", newline="") as handle:
            handle.write("code\tcountries_tags\tproduct_name\tbrands\tcategories_tags\n")
            handle.write("4006381333931\ten:colombia\ttoo-few\n")
            handle.write(
                "036000291452\ten:colombia\tBebida\tMarca\ten:alcoholic-beverages\n"
            )
        metrics = tool.extract(
            input_path=self.input,
            candidates_path=self.candidates,
            evidence_path=self.evidence,
            rejects_path=self.rejects,
            metrics_path=self.metrics,
            source_reference=self.SOURCE_REFERENCE,
            rights_reference=self.RIGHTS_REFERENCE,
            retrieved_at=self.RETRIEVED_AT,
        )
        self.assertEqual(metrics["malformed_csv_rows"], 1)
        self.assertEqual(metrics["excluded_products"], 1)
        self.assertCountEqual(self._reject_codes(), ["malformed_csv_row", "excluded_product"])

    def test_23_candidate_output_is_atomic_when_a11_fails(self) -> None:
        self.candidates.write_text("existing-safe-output\n", encoding="utf-8")
        self._write_dump(self.input, self.HEADERS, [self._row()])
        invalid_report = {"valid": False, "blocking_errors": [{"code": "forced"}]}
        with mock.patch.object(candidate_tool, "validate_candidates", return_value=invalid_report):
            with self.assertRaises(tool.CandidateValidationError):
                tool.extract(
                    input_path=self.input,
                    candidates_path=self.candidates,
                    evidence_path=self.evidence,
                    rejects_path=self.rejects,
                    metrics_path=self.metrics,
                    source_reference=self.SOURCE_REFERENCE,
                    rights_reference=self.RIGHTS_REFERENCE,
                    retrieved_at=self.RETRIEVED_AT,
                )
        self.assertEqual(self.candidates.read_text(encoding="utf-8"), "existing-safe-output\n")
        self.assertFalse(self.evidence.exists())
        self.assertEqual(list(self.root.glob("*.tmp")), [])

    def test_24_no_network_database_or_uuid_generation(self) -> None:
        with (
            mock.patch.object(socket, "socket", side_effect=AssertionError("network used")),
            mock.patch.object(sqlite3, "connect", side_effect=AssertionError("database used")),
            mock.patch.object(uuid, "uuid4", side_effect=AssertionError("uuid used")),
        ):
            metrics = self._extract()
        self.assertFalse(metrics["network_access"])
        self.assertFalse(metrics["database_access"])
        self.assertFalse(metrics["uuid_generation"])

    def test_25_cli_prints_human_report_and_requires_timezone(self) -> None:
        self._write_dump(self.input, self.HEADERS, [self._row()])
        args = [
            "extract",
            "--input",
            str(self.input),
            "--candidates",
            str(self.candidates),
            "--evidence",
            str(self.evidence),
            "--rejects",
            str(self.rejects),
            "--metrics",
            str(self.metrics),
            "--source-reference",
            self.SOURCE_REFERENCE,
            "--rights-reference",
            self.RIGHTS_REFERENCE,
            "--retrieved-at",
            self.RETRIEVED_AT,
        ]
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(tool.main(args), 0)
        self.assertIn("Open Food Facts Colombia extraction: SUCCESS", output.getvalue())
        self.assertIn("Network access: none", output.getvalue())

        with self.assertRaises(tool.OpenFoodFactsBulkError):
            tool.extract(
                input_path=self.input,
                candidates_path=self.candidates,
                evidence_path=self.evidence,
                rejects_path=self.rejects,
                metrics_path=self.metrics,
                source_reference=self.SOURCE_REFERENCE,
                rights_reference=self.RIGHTS_REFERENCE,
                retrieved_at="2026-09-08T12:34:56",
            )


if __name__ == "__main__":
    unittest.main()
