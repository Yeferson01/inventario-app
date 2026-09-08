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
from acquisition import open_prices_bulk as tool  # noqa: E402


class OpenPricesBulkTest(unittest.TestCase):
    SOURCE_REFERENCE = "open-prices:snapshot:2026-09-08"
    RIGHTS_REFERENCE = "https://opendatacommons.org/licenses/odbl/1-0/"
    RETRIEVED_AT = "2026-09-08T12:34:56-05:00"

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.locations = self.root / "locations.jsonl.gz"
        self.prices = self.root / "prices.jsonl.gz"
        self.candidates = self.root / "candidates.csv"
        self.evidence = self.root / "evidence.csv"
        self.rejects = self.root / "rejects.csv"
        self.metrics = self.root / "metrics.json"

    @staticmethod
    def _write_gzip(path: Path, rows: list[dict[str, object] | str]) -> None:
        with gzip.open(path, "wt", encoding="utf-8", newline="") as handle:
            for row in rows:
                if isinstance(row, str):
                    handle.write(row)
                else:
                    handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True))
                handle.write("\n")

    @staticmethod
    def _location(location_id: int, country: str) -> dict[str, object]:
        return {"id": location_id, "osm_address_country_code": country, "name": "ignored"}

    @staticmethod
    def _price(
        price_id: int,
        code: object = "4006381333931",
        location_id: object = 1,
        **overrides: object,
    ) -> dict[str, object]:
        row: dict[str, object] = {
            "id": price_id,
            "type": "PRODUCT",
            "product_code": code,
            "product_name": "Producto",
            "location_id": location_id,
            "date": "2026-09-01",
            "duplicate_of": None,
            "price": 1234,
            "owner": "must-not-leak",
        }
        row.update(overrides)
        return row

    def _extract(
        self,
        location_rows: list[dict[str, object] | str] | None = None,
        price_rows: list[dict[str, object] | str] | None = None,
        *,
        max_candidates: int | None = None,
    ) -> dict[str, object]:
        self._write_gzip(
            self.locations,
            location_rows if location_rows is not None else [self._location(1, "CO")],
        )
        self._write_gzip(
            self.prices,
            price_rows if price_rows is not None else [self._price(10)],
        )
        return tool.extract(
            locations_path=self.locations,
            prices_path=self.prices,
            candidates_path=self.candidates,
            evidence_path=self.evidence,
            rejects_path=self.rejects,
            metrics_path=self.metrics,
            source_reference=self.SOURCE_REFERENCE,
            rights_reference=self.RIGHTS_REFERENCE,
            retrieved_at=self.RETRIEVED_AT,
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

    def test_01_colombia_country_code_is_trimmed_and_casefolded(self) -> None:
        metrics = self._extract(
            [self._location(1, " CO "), self._location(2, "co"), self._location(3, "US")],
            [self._price(10, location_id=1), self._price(11, location_id=2), self._price(12, location_id=3)],
        )
        self.assertEqual(metrics["locations_colombia"], 2)
        self.assertEqual(metrics["prices_non_colombia_location"], 1)
        self.assertEqual(len(self._candidate_rows()), 1)
        self.assertNotIn("non_colombia_location", self._reject_codes())

    def test_02_valid_colombia_product_creates_candidate_and_evidence(self) -> None:
        metrics = self._extract()
        self.assertEqual(metrics["accepted_candidates"], 1)
        self.assertEqual(len(self._candidate_rows()), 1)
        evidence = self._csv_rows(self.evidence)
        self.assertEqual(len(evidence), 1)
        self.assertEqual(evidence[0]["location_id"], "1")
        self.assertNotIn("owner", evidence[0])
        self.assertNotIn("price", evidence[0])

    def test_03_category_missing_code_and_missing_location_are_rejected(self) -> None:
        prices = [
            self._price(1, type="CATEGORY"),
            self._price(2, code=""),
            self._price(3, location_id=None),
        ]
        metrics = self._extract(price_rows=prices)
        self.assertEqual(metrics["accepted_candidates"], 0)
        self.assertCountEqual(
            self._reject_codes(),
            ["non_product_price", "empty_product_code", "missing_location_id"],
        )

    def test_04_invalid_checksum_and_unsupported_length_are_rejected(self) -> None:
        metrics = self._extract(
            price_rows=[self._price(1, "4006381333932"), self._price(2, "123456789")]
        )
        self.assertEqual(metrics["invalid_checksum"], 1)
        self.assertEqual(metrics["unsupported_barcode"], 1)
        self.assertCountEqual(
            self._reject_codes(), ["invalid_barcode", "unsupported_barcode_length"]
        )

    def test_05_leading_zero_and_exterior_whitespace_are_preserved(self) -> None:
        self._extract(price_rows=[self._price(1, " 036000291452 ")])
        row = self._candidate_rows()[0]
        self.assertEqual(row["raw_barcode"], " 036000291452 ")
        self.assertEqual(row["barcode"], "036000291452")
        self.assertEqual(row["barcode_type"], "upc")

    def test_06_scientific_notation_and_numeric_json_code_are_rejected(self) -> None:
        metrics = self._extract(
            price_rows=[self._price(1, "4.006381333931E12"), self._price(2, 4006381333931)]
        )
        self.assertEqual(metrics["scientific_notation"], 1)
        self.assertEqual(metrics["invalid_barcode"], 2)
        self.assertEqual(self._reject_codes(), ["invalid_barcode", "invalid_barcode"])

    def test_07_same_location_counts_once_but_keeps_each_observation(self) -> None:
        self._extract(price_rows=[self._price(1), self._price(2), self._price(3)])
        rows = self._candidate_rows()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["colombia_evidence_count"], "1")
        self.assertEqual(len(self._csv_rows(self.evidence)), 3)

    def test_08_two_colombia_locations_count_as_two(self) -> None:
        self._extract(
            location_rows=[self._location(1, "CO"), self._location(2, "CO")],
            price_rows=[self._price(1, location_id=1), self._price(2, location_id=2)],
        )
        self.assertEqual(self._candidate_rows()[0]["colombia_evidence_count"], "2")

    def test_09_duplicate_of_and_repeated_observation_do_not_add_evidence(self) -> None:
        original = self._price(1)
        metrics = self._extract(
            price_rows=[original, self._price(2, duplicate_of=1), dict(original)]
        )
        self.assertEqual(metrics["duplicate_price_observations_skipped"], 2)
        self.assertEqual(len(self._csv_rows(self.evidence)), 1)
        self.assertEqual(self._reject_codes().count("duplicate_source_observation"), 2)

    def test_10_consistent_normalized_name_is_kept(self) -> None:
        self._extract(
            price_rows=[
                self._price(1, product_name=" Café   Uno "),
                self._price(2, product_name="Café Uno"),
            ]
        )
        self.assertEqual(self._candidate_rows()[0]["name_if_known"], "Café Uno")
        self.assertEqual(self._candidate_rows()[0]["notes"], "")

    def test_11_conflicting_names_stay_blank_and_are_audited(self) -> None:
        metrics = self._extract(
            price_rows=[
                self._price(1, product_name="Producto A"),
                self._price(2, product_name="Producto B"),
            ]
        )
        candidate = self._candidate_rows()[0]
        self.assertEqual(candidate["name_if_known"], "")
        self.assertEqual(candidate["notes"], "name_conflict")
        self.assertEqual(metrics["candidate_name_conflicts"], 1)
        self.assertTrue(all(row["name_conflict"] == "true" for row in self._csv_rows(self.evidence)))

    def test_12_candidate_uses_exact_a11_open_prices_contract(self) -> None:
        self._extract()
        row = self._candidate_rows()[0]
        self.assertEqual(list(row), candidate_tool.CANDIDATE_HEADERS)
        self.assertEqual(row["source"], "open_dataset")
        self.assertEqual(row["source_channel"], "open_prices")
        self.assertEqual(row["rights_class"], "open_dataset_odbl_share_alike")
        self.assertEqual(row["can_persist_candidate"], "true")
        self.assertEqual(row["candidate_confidence"], "medium")
        self.assertEqual(row["colombia_evidence_type"], "other_documented")
        self.assertEqual(row["brand_if_known"], "")
        report = candidate_tool.validate_candidates(input_path=self.candidates)
        self.assertTrue(report["valid"], report["blocking_errors"])

    def test_13_hash_and_logical_outputs_ignore_jsonl_order(self) -> None:
        locations = [self._location(2, "co"), self._location(1, "CO")]
        prices = [self._price(2, location_id=2), self._price(1, location_id=1)]
        self._extract(locations, prices)
        first_candidates = self.candidates.read_bytes()
        first_evidence = self.evidence.read_bytes()
        first_hash = self._candidate_rows()[0]["source_content_sha256"]

        self._extract(list(reversed(locations)), list(reversed(prices)))
        self.assertEqual(self.candidates.read_bytes(), first_candidates)
        self.assertEqual(self.evidence.read_bytes(), first_evidence)
        self.assertEqual(self._candidate_rows()[0]["source_content_sha256"], first_hash)

    def test_14_max_candidates_uses_location_then_observation_ranking(self) -> None:
        locations = [self._location(1, "CO"), self._location(2, "CO")]
        prices = [
            self._price(1, "4006381333931", 1),
            self._price(2, "4006381333931", 2),
            self._price(3, "96385074", 1),
            self._price(4, "96385074", 1),
            self._price(5, "96385074", 1),
            self._price(6, "036000291452", 1),
        ]
        metrics = self._extract(locations, prices, max_candidates=2)
        self.assertEqual(
            [row["barcode"] for row in self._candidate_rows()],
            ["4006381333931", "96385074"],
        )
        self.assertEqual(metrics["unique_valid_gtins"], 3)
        self.assertEqual(metrics["accepted_candidates"], 2)
        self.assertTrue(metrics["max_candidates_applied"])

    def test_15_input_gzip_files_are_not_modified(self) -> None:
        self._write_gzip(self.locations, [self._location(1, "CO")])
        self._write_gzip(self.prices, [self._price(1)])
        before = {
            path: hashlib.sha256(path.read_bytes()).hexdigest()
            for path in (self.locations, self.prices)
        }
        tool.extract(
            locations_path=self.locations,
            prices_path=self.prices,
            candidates_path=self.candidates,
            evidence_path=self.evidence,
            rejects_path=self.rejects,
            metrics_path=self.metrics,
            source_reference=self.SOURCE_REFERENCE,
            rights_reference=self.RIGHTS_REFERENCE,
            retrieved_at=self.RETRIEVED_AT,
        )
        after = {
            path: hashlib.sha256(path.read_bytes()).hexdigest()
            for path in (self.locations, self.prices)
        }
        self.assertEqual(after, before)

    def test_16_malformed_json_and_missing_location_fields_are_safe(self) -> None:
        metrics = self._extract(
            location_rows=[
                "{broken",
                {"osm_address_country_code": "CO"},
                {"id": 3},
                self._location(1, "CO"),
            ],
            price_rows=["not-json", self._price(1)],
        )
        self.assertEqual(metrics["locations_malformed_json"], 1)
        self.assertEqual(metrics["locations_missing_id"], 1)
        self.assertEqual(metrics["locations_missing_country_code"], 1)
        self.assertEqual(metrics["prices_malformed_json"], 1)
        self.assertEqual(metrics["accepted_candidates"], 1)
        self.assertEqual(self._reject_codes().count("malformed_json"), 2)

    def test_17_incompatible_schema_fails_without_publishing_outputs(self) -> None:
        self._write_gzip(self.locations, [{"unexpected": "shape"}])
        self._write_gzip(self.prices, [self._price(1)])
        with self.assertRaises(tool.OpenPricesBulkError):
            tool.extract(
                locations_path=self.locations,
                prices_path=self.prices,
                candidates_path=self.candidates,
                evidence_path=self.evidence,
                rejects_path=self.rejects,
                metrics_path=self.metrics,
                source_reference=self.SOURCE_REFERENCE,
                rights_reference=self.RIGHTS_REFERENCE,
                retrieved_at=self.RETRIEVED_AT,
            )
        self.assertFalse(self.candidates.exists())
        self.assertFalse(self.evidence.exists())

    def test_18_candidate_output_is_not_replaced_when_a11_validation_fails(self) -> None:
        self.candidates.write_text("existing-safe-output\n", encoding="utf-8")
        self._write_gzip(self.locations, [self._location(1, "CO")])
        self._write_gzip(self.prices, [self._price(1)])
        invalid_report = {"valid": False, "blocking_errors": [{"code": "forced"}]}
        with mock.patch.object(candidate_tool, "validate_candidates", return_value=invalid_report):
            with self.assertRaises(tool.CandidateValidationError):
                tool.extract(
                    locations_path=self.locations,
                    prices_path=self.prices,
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

    def test_19_generated_200_prefix_and_explicit_restricted_flag_are_rejected(self) -> None:
        metrics = self._extract(
            price_rows=[
                self._price(1, "2000000152012"),
                self._price(2, "4006381333931", age_restricted=True),
            ]
        )
        self.assertEqual(metrics["generated_or_internal_identifier"], 1)
        self.assertEqual(metrics["restricted_products"], 1)
        self.assertCountEqual(
            self._reject_codes(), ["generated_or_internal_identifier", "restricted_product"]
        )

    def test_20_no_network_database_or_uuid_side_effects(self) -> None:
        with (
            mock.patch.object(socket, "socket", side_effect=AssertionError("network used")),
            mock.patch.object(sqlite3, "connect", side_effect=AssertionError("database used")),
            mock.patch.object(uuid, "uuid4", side_effect=AssertionError("uuid used")),
        ):
            metrics = self._extract()
        self.assertFalse(metrics["network_access"])
        self.assertFalse(metrics["database_access"])
        self.assertFalse(metrics["uuid_generation"])

    def test_21_cli_requires_explicit_timezone_aware_timestamp_and_prints_report(self) -> None:
        self._write_gzip(self.locations, [self._location(1, "CO")])
        self._write_gzip(self.prices, [self._price(1)])
        args = [
            "extract",
            "--locations",
            str(self.locations),
            "--prices",
            str(self.prices),
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
        self.assertIn("Open Prices Colombia extraction: SUCCESS", output.getvalue())
        self.assertIn("Network access: none", output.getvalue())

        with self.assertRaises(tool.OpenPricesBulkError):
            tool.extract(
                locations_path=self.locations,
                prices_path=self.prices,
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
