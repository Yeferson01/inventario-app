from __future__ import annotations

import csv
import io
import socket
import sqlite3
import sys
import tempfile
import unittest
import uuid
from contextlib import redirect_stderr, redirect_stdout
from copy import deepcopy
from pathlib import Path
from unittest import mock


TOOL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL_DIR))

from acquisition import candidate_tool as tool  # noqa: E402


class CandidateToolTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    @staticmethod
    def _valid_row() -> dict[str, str]:
        return {
            "raw_barcode": "4006381333931",
            "barcode": "4006381333931",
            "barcode_type": "ean13",
            "name_if_known": "Producto de prueba",
            "brand_if_known": "Marca de prueba",
            "source": "supplier",
            "source_channel": "supplier_feed",
            "source_reference": "contract:test-supplier:2026",
            "source_record_id": "supplier-row-1",
            "retrieved_at": "2026-09-08T12:34:56Z",
            "rights_class": "authorized_contract",
            "rights_reference": "contract:test-supplier:2026",
            "can_persist_candidate": "true",
            "candidate_confidence": "high",
            "colombia_evidence_type": "authorized_distributor",
            "colombia_evidence_count": "1",
            "source_content_sha256": "a" * 64,
            "notes": "",
        }

    @staticmethod
    def _codes(report: dict[str, object]) -> set[str]:
        return {issue["code"] for issue in report["blocking_errors"]}  # type: ignore[index]

    def _write_csv(self, path: Path, rows: list[dict[str, str]]) -> None:
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=tool.CANDIDATE_HEADERS, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)

    def _report(self, rows: list[dict[str, str]]) -> dict[str, object]:
        path = self.root / "catalog_candidates.csv"
        self._write_csv(path, rows)
        return tool.validate_candidates(input_path=path)

    def test_01_header_only_candidate_csv_is_valid(self) -> None:
        report = self._report([])
        self.assertTrue(report["valid"])
        self.assertEqual(report["candidate_rows"], 0)

    def test_02_valid_ean13(self) -> None:
        self.assertTrue(self._report([self._valid_row()])["valid"])

    def test_03_valid_ean8(self) -> None:
        row = self._valid_row()
        row.update(raw_barcode="96385074", barcode="96385074", barcode_type="ean8")
        self.assertTrue(self._report([row])["valid"])

    def test_04_valid_upc(self) -> None:
        row = self._valid_row()
        row.update(raw_barcode="036000291452", barcode="036000291452", barcode_type="upc")
        self.assertTrue(self._report([row])["valid"])

    def test_05_valid_gtin14(self) -> None:
        row = self._valid_row()
        row.update(raw_barcode="10012345000017", barcode="10012345000017", barcode_type="gtin")
        self.assertTrue(self._report([row])["valid"])

    def test_06_invalid_checksum_blocks(self) -> None:
        row = self._valid_row()
        row.update(raw_barcode="4006381333932", barcode="4006381333932")
        self.assertIn("invalid_barcode", self._codes(self._report([row])))

    def test_07_scientific_notation_blocks(self) -> None:
        row = self._valid_row()
        row.update(raw_barcode="4.006381333931E+12", barcode="4.006381333931E+12")
        self.assertIn("invalid_barcode", self._codes(self._report([row])))

    def test_08_leading_zero_is_preserved(self) -> None:
        row = self._valid_row()
        row.update(
            raw_barcode=" 036000291452 ",
            barcode="036000291452",
            barcode_type="upc",
        )
        report = self._report([row])
        self.assertTrue(report["valid"])
        self.assertEqual(report["normalized_preview"][0]["barcode"], "036000291452")  # type: ignore[index]

    def test_09_wrong_barcode_type_blocks(self) -> None:
        row = self._valid_row()
        row["barcode_type"] = "gtin"
        self.assertIn("invalid_barcode", self._codes(self._report([row])))

    def test_10_duplicate_barcode_blocks(self) -> None:
        first = self._valid_row()
        second = deepcopy(first)
        second["source_record_id"] = "supplier-row-2"
        report = self._report([first, second])
        self.assertIn("duplicate_barcode", self._codes(report))
        self.assertEqual(report["duplicate_barcode_count"], 1)

    def test_11_unknown_p12_source_blocks(self) -> None:
        row = self._valid_row()
        row["source"] = "invented_source"
        self.assertIn("invalid_source", self._codes(self._report([row])))

    def test_12_unknown_source_channel_blocks(self) -> None:
        row = self._valid_row()
        row["source_channel"] = "invented_channel"
        self.assertIn("invalid_source_channel", self._codes(self._report([row])))

    def test_13_false_persistence_blocks(self) -> None:
        row = self._valid_row()
        row["can_persist_candidate"] = "false"
        self.assertIn("candidate_not_persistable", self._codes(self._report([row])))

    def test_14_low_confidence_blocks(self) -> None:
        row = self._valid_row()
        row["candidate_confidence"] = "low"
        self.assertIn("invalid_candidate_confidence", self._codes(self._report([row])))

    def test_15_naive_timestamp_blocks(self) -> None:
        row = self._valid_row()
        row["retrieved_at"] = "2026-09-08T12:34:56"
        self.assertIn("invalid_retrieved_at", self._codes(self._report([row])))

    def test_16_invalid_sha256_blocks(self) -> None:
        row = self._valid_row()
        row["source_content_sha256"] = "not-a-sha256"
        self.assertIn("invalid_source_content_sha256", self._codes(self._report([row])))

    def test_17_zero_colombia_evidence_count_blocks(self) -> None:
        row = self._valid_row()
        row["colombia_evidence_count"] = "0"
        self.assertIn("invalid_colombia_evidence_count", self._codes(self._report([row])))

    def test_18_unknown_colombia_evidence_type_blocks(self) -> None:
        row = self._valid_row()
        row["colombia_evidence_type"] = "name_match"
        self.assertIn("invalid_colombia_evidence_type", self._codes(self._report([row])))

    def test_19_name_and_brand_may_be_empty(self) -> None:
        row = self._valid_row()
        row.update(name_if_known="", brand_if_known="")
        self.assertTrue(self._report([row])["valid"])

    def test_20_validation_does_not_modify_the_file(self) -> None:
        path = self.root / "catalog_candidates.csv"
        self._write_csv(path, [self._valid_row()])
        before = path.read_bytes()
        tool.validate_candidates(input_path=path)
        self.assertEqual(path.read_bytes(), before)

    def test_21_validation_has_zero_network_and_database_access(self) -> None:
        path = self.root / "catalog_candidates.csv"
        self._write_csv(path, [self._valid_row()])
        with (
            mock.patch.object(socket, "socket", side_effect=AssertionError("network access attempted")),
            mock.patch.object(
                sqlite3,
                "connect",
                side_effect=AssertionError("database access attempted"),
            ),
        ):
            report = tool.validate_candidates(input_path=path)
        self.assertTrue(report["valid"])
        self.assertFalse(report["network_access"])
        self.assertFalse(report["database_access"])

    def test_22_acquisition_does_not_generate_or_assign_uuids(self) -> None:
        path = self.root / "catalog_candidates.csv"
        self._write_csv(path, [self._valid_row()])
        with mock.patch.object(uuid, "uuid4", side_effect=AssertionError("UUID generation attempted")):
            report = tool.validate_candidates(input_path=path)
        self.assertTrue(report["valid"])
        self.assertFalse(any("uuid" in header.casefold() for header in tool.CANDIDATE_HEADERS))

    def test_23_main_returns_zero_or_one_for_content_validation(self) -> None:
        path = self.root / "catalog_candidates.csv"
        self._write_csv(path, [self._valid_row()])
        with redirect_stdout(io.StringIO()):
            self.assertEqual(tool.main(["validate", "--input", str(path)]), 0)

        invalid = self._valid_row()
        invalid["can_persist_candidate"] = "false"
        self._write_csv(path, [invalid])
        with redirect_stdout(io.StringIO()):
            self.assertEqual(tool.main(["validate", "--input", str(path)]), 1)

    def test_24_main_returns_two_for_missing_input(self) -> None:
        missing = self.root / "missing.csv"
        with redirect_stderr(io.StringIO()):
            self.assertEqual(tool.main(["validate", "--input", str(missing)]), 2)

    def test_25_sha256_is_normalized_to_lowercase_for_reporting(self) -> None:
        row = self._valid_row()
        row["source_content_sha256"] = "ABCDEF" * 10 + "ABCD"
        report = self._report([row])
        self.assertTrue(report["valid"])
        self.assertEqual(
            report["normalized_preview"][0]["source_content_sha256"],  # type: ignore[index]
            row["source_content_sha256"].lower(),
        )

    def test_26_explicit_non_utc_offset_is_accepted(self) -> None:
        row = self._valid_row()
        row["retrieved_at"] = "2026-09-08T07:34:56-05:00"
        self.assertTrue(self._report([row])["valid"])


if __name__ == "__main__":
    unittest.main()
