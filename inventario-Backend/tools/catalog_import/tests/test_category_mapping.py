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
from pathlib import Path
from unittest import mock


TOOL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL_DIR))

import catalog_tool  # noqa: E402
from resolution import candidate_resolution  # noqa: E402
from resolution import category_mapping as tool  # noqa: E402


class CategoryMappingTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.resolution = self.root / "resolution.csv"
        self.rules = self.root / "rules.json"
        self.output = self.root / "category-mapping.csv"
        self.metrics = self.root / "metrics.json"
        self.categories = tool._load_categories()

    @staticmethod
    def _resolution_row(
        barcode: str = "4006381333931",
        *,
        main_category: str = "",
        categories_tags: str = "en:sodas",
        **overrides: str,
    ) -> dict[str, str]:
        has_evidence = bool(main_category.strip() or categories_tags.strip())
        row = {
            "barcode": barcode,
            "barcode_type": "ean13",
            "candidate_name_if_known": "Candidate name",
            "candidate_brand_if_known": "Candidate brand",
            "off_product_name": "OFF Product",
            "off_brands": "OFF Brand",
            "off_categories_tags": categories_tags,
            "off_main_category": main_category,
            "off_quantity": "500 g",
            "off_last_modified_t": "1788800000",
            "name_status": "available",
            "brand_status": "available",
            "category_status": "available" if has_evidence else "missing",
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
    def _rule(
        rule_id: str,
        *,
        action: str = "map",
        tags: list[str] | None = None,
        main_tags: list[str] | None = None,
        target: str | None = "Alimentos",
        reason: str = "test reason",
    ) -> dict[str, object]:
        if action != "map" and target == "Alimentos":
            target = None
        if tags is None and main_tags is None:
            tags = ["en:test-tag"]
        return {
            "rule_id": rule_id,
            "action": action,
            "match_main_category_any": main_tags or [],
            "match_tags_any": tags or [],
            "target_category": target,
            "reason": reason,
        }

    def _write_resolution(
        self,
        rows: list[dict[str, str]],
        headers: list[str] | None = None,
    ) -> None:
        with self.resolution.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(
                handle,
                fieldnames=headers or candidate_resolution.RESOLUTION_HEADERS,
                extrasaction="ignore",
                lineterminator="\n",
            )
            writer.writeheader()
            writer.writerows(rows)

    def _write_rules(
        self,
        rules: list[dict[str, object]],
        *,
        version: str | None = "test-1",
    ) -> None:
        payload: dict[str, object] = {"rules": rules}
        if version is not None:
            payload["ruleset_version"] = version
        self.rules.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    def _map(
        self,
        rows: list[dict[str, str]] | None = None,
        rules: list[dict[str, object]] | None = None,
    ) -> dict[str, object]:
        self._write_resolution(rows or [self._resolution_row()])
        rules_path = tool.DEFAULT_RULES_PATH
        if rules is not None:
            self._write_rules(rules)
            rules_path = self.rules
        return tool.map_categories(
            resolution_path=self.resolution,
            rules_path=rules_path,
            output_path=self.output,
            metrics_path=self.metrics,
        )

    @staticmethod
    def _csv_rows(path: Path) -> list[dict[str, str]]:
        with path.open("r", encoding="utf-8", newline="") as handle:
            return list(csv.DictReader(handle))

    def _mapping_rows(self) -> list[dict[str, str]]:
        return self._csv_rows(self.output)

    def test_01_shipped_ruleset_is_valid_and_versioned(self) -> None:
        ruleset = tool.load_ruleset(tool.DEFAULT_RULES_PATH, self.categories)
        self.assertEqual(ruleset.ruleset_version, "1.2.0")
        self.assertEqual(len(ruleset.rules), 9)
        self.assertRegex(ruleset.ruleset_sha256, r"^[0-9a-f]{64}$")

    def test_02_ruleset_version_is_required(self) -> None:
        for version in (None, "", "  "):
            with self.subTest(version=version):
                self._write_rules([self._rule("rule-a")], version=version)
                with self.assertRaisesRegex(tool.CategoryMappingToolError, "ruleset_version"):
                    tool.load_ruleset(self.rules, self.categories)

    def test_03_duplicate_rule_id_blocks(self) -> None:
        self._write_rules([self._rule("duplicate"), self._rule("duplicate")])
        with self.assertRaisesRegex(tool.CategoryMappingToolError, "Duplicate rule_id"):
            tool.load_ruleset(self.rules, self.categories)

    def test_04_invalid_action_blocks(self) -> None:
        self._write_rules([self._rule("bad-action", action="guess")])
        with self.assertRaisesRegex(tool.CategoryMappingToolError, "invalid action"):
            tool.load_ruleset(self.rules, self.categories)

    def test_05_unknown_target_category_blocks(self) -> None:
        self._write_rules([self._rule("bad-target", target="Inventada")])
        with self.assertRaisesRegex(tool.CategoryMappingToolError, "P1.2 vocabulary"):
            tool.load_ruleset(self.rules, self.categories)

    def test_06_action_target_contract_is_enforced(self) -> None:
        cases = [
            self._rule("map-null", target=None),
            self._rule("review-target", action="review", target="Bebidas"),
            self._rule("exclude-target", action="exclude", target="Bebidas"),
        ]
        for rule in cases:
            with self.subTest(rule_id=rule["rule_id"]):
                self._write_rules([rule])
                with self.assertRaises(tool.CategoryMappingToolError):
                    tool.load_ruleset(self.rules, self.categories)

    def test_07_rule_tags_must_be_exact_and_normalized(self) -> None:
        for tag in (" EN:SODAS", "en:sodas ", "en:bad tag", "en:sodas,other"):
            with self.subTest(tag=tag):
                self._write_rules([self._rule("bad-tag", tags=[tag])])
                with self.assertRaisesRegex(tool.CategoryMappingToolError, "normalized OFF tag"):
                    tool.load_ruleset(self.rules, self.categories)

    def test_08_matching_is_exact_case_insensitive_and_trimmed(self) -> None:
        rows = [
            self._resolution_row("1", categories_tags="EN:SODAS"),
            self._resolution_row("2", categories_tags=" en:sodas "),
            self._resolution_row("3", categories_tags="en:other-sodas-example"),
        ]
        self._map(rows)
        mapped = {row["barcode"]: row for row in self._mapping_rows()}
        self.assertEqual(mapped["1"]["cronos_category_candidate"], "Bebidas")
        self.assertEqual(mapped["2"]["cronos_category_candidate"], "Bebidas")
        self.assertEqual(mapped["3"]["mapping_status"], "unresolved")

    def test_09_matches_main_category_and_categories_tags_only(self) -> None:
        rows = [
            self._resolution_row("1", main_category="en:breads", categories_tags=""),
            self._resolution_row("2", main_category="", categories_tags="en:biscuits"),
            self._resolution_row(
                "3",
                main_category="en:unknown",
                categories_tags="en:unknown",
                off_product_name="Soda",
                off_brands="en:sodas",
            ),
        ]
        self._map(rows)
        mapped = {row["barcode"]: row for row in self._mapping_rows()}
        self.assertEqual(mapped["1"]["cronos_category_candidate"], "Alimentos")
        self.assertEqual(mapped["2"]["cronos_category_candidate"], "Snacks y confitería")
        self.assertEqual(mapped["3"]["mapping_status"], "unresolved")

    def test_10_multiple_tags_for_same_category_map_once(self) -> None:
        self._map(
            [self._resolution_row(categories_tags="en:biscuits,en:salty-snacks")]
        )
        row = self._mapping_rows()[0]
        self.assertEqual(row["mapping_status"], "mapped")
        self.assertEqual(row["cronos_category_candidate"], "Snacks y confitería")
        self.assertEqual(row["matched_off_tags"], "en:biscuits|en:salty-snacks")

    def test_11_multiple_map_rules_same_target_remain_mapped(self) -> None:
        rules = [
            self._rule("map-a", tags=["en:tag-a"]),
            self._rule("map-b", tags=["en:tag-b"]),
        ]
        self._map([self._resolution_row(categories_tags="en:tag-b,en:tag-a")], rules)
        row = self._mapping_rows()[0]
        self.assertEqual(row["mapping_status"], "mapped")
        self.assertEqual(row["cronos_category_candidate"], "Alimentos")
        self.assertEqual(row["mapping_rule_ids"], "map-a|map-b")

    def test_12_multiple_map_targets_require_ambiguous_review(self) -> None:
        rules = [
            self._rule("map-food", tags=["en:tag-a"]),
            self._rule("map-drink", tags=["en:tag-b"], target="Bebidas"),
        ]
        self._map([self._resolution_row(categories_tags="en:tag-a,en:tag-b")], rules)
        row = self._mapping_rows()[0]
        self.assertEqual(row["mapping_status"], "review")
        self.assertEqual(row["cronos_category_candidate"], "")
        self.assertEqual(row["mapping_reason"], "ambiguous_target")

    def test_13_review_alone_and_review_plus_map_follow_precedence(self) -> None:
        self._map(
            [
                self._resolution_row("1", categories_tags="en:groceries"),
                self._resolution_row("2", categories_tags="en:groceries,en:breads"),
            ]
        )
        rows = {row["barcode"]: row for row in self._mapping_rows()}
        self.assertEqual(rows["1"]["mapping_status"], "review")
        self.assertEqual(rows["1"]["mapping_reason"], "review_required")
        self.assertEqual(rows["2"]["mapping_status"], "mapped")
        self.assertEqual(rows["2"]["cronos_category_candidate"], "Alimentos")
        self.assertIn("review-contextual-or-broad-tags", rows["2"]["mapping_rule_ids"])

    def test_14_exclude_overrides_map(self) -> None:
        self._map(
            [
                self._resolution_row("1", categories_tags="en:alcoholic-beverages"),
                self._resolution_row(
                    "2", categories_tags="en:alcoholic-beverages,en:sodas"
                ),
            ]
        )
        for row in self._mapping_rows():
            self.assertEqual(row["mapping_status"], "excluded")
            self.assertEqual(row["cronos_category_candidate"], "")
            self.assertEqual(row["mapping_reason"], "out_of_scope_for_initial_catalog")

    def test_15_unresolved_reasons_distinguish_missing_and_unmatched(self) -> None:
        self._map(
            [
                self._resolution_row("1", categories_tags=""),
                self._resolution_row("2", categories_tags="en:unknown"),
            ]
        )
        rows = {row["barcode"]: row for row in self._mapping_rows()}
        self.assertEqual(rows["1"]["mapping_reason"], "no_category_evidence")
        self.assertEqual(rows["2"]["mapping_reason"], "no_matching_rule")
        self.assertEqual(rows["2"]["mapping_rule_ids"], "")
        self.assertEqual(rows["2"]["matched_off_tags"], "")

    def test_16_shipped_v1_rules_cover_only_reviewed_tags(self) -> None:
        expected = {
            "Alimentos": [
                "en:breakfast-cereals",
                "en:greek-style-yogurts",
                "en:yogurts",
                "en:cheeses",
                "en:breads",
                "en:rolled-oats",
                "en:rices",
                "en:arepas",
                "en:canned-tunas",
            ],
            "Bebidas": [
                "en:sweetened-beverages",
                "en:energy-drinks",
                "en:instant-coffees",
                "en:milks",
                "en:almond-based-drinks",
                "en:sodas",
                "en:iced-teas",
            ],
            "Snacks y confitería": [
                "en:biscuits",
                "en:salty-snacks",
                "en:dry-biscuits",
                "en:crisps",
                "en:cereal-bars",
                "en:confectioneries",
                "en:gummi-candies",
                "en:ice-creams",
            ],
            "review": [
                "en:groceries",
                "en:peanuts",
                "en:dairies",
                "en:jelly-desserts",
            ],
            "excluded": ["en:dietary-supplements", "en:alcoholic-beverages"],
        }
        rows: list[dict[str, str]] = []
        expected_by_barcode: dict[str, tuple[str, str]] = {}
        counter = 1
        for outcome, tags in expected.items():
            for tag in tags:
                barcode = f"{counter:03}"
                rows.append(self._resolution_row(barcode, categories_tags=tag))
                status = "mapped" if outcome in self.categories else outcome
                category = outcome if status == "mapped" else ""
                expected_by_barcode[barcode] = (status, category)
                counter += 1
        self._map(rows)
        actual = {row["barcode"]: row for row in self._mapping_rows()}
        for barcode, (status, category) in expected_by_barcode.items():
            with self.subTest(barcode=barcode):
                self.assertEqual(actual[barcode]["mapping_status"], status)
                self.assertEqual(actual[barcode]["cronos_category_candidate"], category)

    def test_17_personal_care_is_exact_only_and_no_household_rule_is_invented(self) -> None:
        ruleset = tool.load_ruleset(tool.DEFAULT_RULES_PATH, self.categories)
        targets = {rule.target_category for rule in ruleset.rules if rule.action == "map"}
        self.assertNotIn("Aseo del hogar", targets)
        personal_rules = [
            rule
            for rule in ruleset.rules
            if rule.action == "map" and rule.target_category == "Cuidado personal"
        ]
        self.assertEqual(len(personal_rules), 1)
        self.assertEqual(personal_rules[0].match_main_category_any, ("es:maquillaje",))
        self.assertEqual(personal_rules[0].match_tags_any, ())

    def test_18_rule_ids_and_matched_tags_are_deterministic(self) -> None:
        rules = [
            self._rule("z-rule", tags=["en:z", "en:a"]),
            self._rule("a-rule", tags=["en:b"]),
        ]
        self._map(
            [self._resolution_row(categories_tags=" en:z,EN:B,en:a,en:b ")],
            rules,
        )
        row = self._mapping_rows()[0]
        self.assertEqual(row["mapping_rule_ids"], "a-rule|z-rule")
        self.assertEqual(row["matched_off_tags"], "en:a|en:b|en:z")

    def test_19_ruleset_hash_ignores_rule_and_tag_order(self) -> None:
        rules_a = [
            self._rule("rule-b", tags=["en:z", "en:a"]),
            self._rule("rule-a", tags=["en:b"]),
        ]
        self._write_rules(rules_a)
        first = tool.load_ruleset(self.rules, self.categories)
        second_path = self.root / "rules-second.json"
        payload = {
            "ruleset_version": "test-1",
            "rules": [
                self._rule("rule-a", tags=["en:b"]),
                self._rule("rule-b", tags=["en:a", "en:z"]),
            ],
        }
        second_path.write_text(json.dumps(payload), encoding="utf-8")
        second = tool.load_ruleset(second_path, self.categories)
        self.assertEqual(first.ruleset_sha256, second.ruleset_sha256)

    def test_20_mapping_record_hash_is_deterministic_and_factual(self) -> None:
        self._map()
        first = self._mapping_rows()[0]
        first_hash = first["category_mapping_record_sha256"]
        self._map()
        self.assertEqual(
            self._mapping_rows()[0]["category_mapping_record_sha256"], first_hash
        )
        self._map([self._resolution_row(categories_tags="en:breads")])
        self.assertNotEqual(
            self._mapping_rows()[0]["category_mapping_record_sha256"], first_hash
        )

    def test_21_duplicate_resolution_barcode_blocks(self) -> None:
        self._write_resolution([self._resolution_row(), self._resolution_row()])
        with self.assertRaisesRegex(
            tool.CategoryMappingValidationError, "Duplicate resolution barcode"
        ):
            tool.map_categories(
                resolution_path=self.resolution,
                rules_path=tool.DEFAULT_RULES_PATH,
                output_path=self.output,
                metrics_path=self.metrics,
            )

    def test_22_invalid_or_inconsistent_resolution_hash_blocks(self) -> None:
        cases = [
            self._resolution_row(resolution_record_sha256="invalid"),
            self._resolution_row(resolution_record_sha256="c" * 64),
        ]
        for row in cases:
            with self.subTest(value=row["resolution_record_sha256"]):
                self._write_resolution([row])
                with self.assertRaisesRegex(
                    tool.CategoryMappingValidationError,
                    "resolution_record_sha256",
                ):
                    tool.map_categories(
                        resolution_path=self.resolution,
                        rules_path=tool.DEFAULT_RULES_PATH,
                        output_path=self.output,
                        metrics_path=self.metrics,
                    )

    def test_23_resolution_status_contract_is_enforced(self) -> None:
        cases = [
            self._resolution_row(source_match_status="missing"),
            self._resolution_row(category_status="invented"),
        ]
        for row in cases:
            with self.subTest(row=row):
                row["resolution_record_sha256"] = catalog_tool.record_hash(
                    {
                        header: row[header]
                        for header in candidate_resolution.RESOLUTION_HEADERS
                        if header != "resolution_record_sha256"
                    }
                )
                self._write_resolution([row])
                with self.assertRaises(tool.CategoryMappingValidationError):
                    tool.map_categories(
                        resolution_path=self.resolution,
                        rules_path=tool.DEFAULT_RULES_PATH,
                        output_path=self.output,
                        metrics_path=self.metrics,
                    )

    def test_24_resolution_header_must_be_exact(self) -> None:
        headers = candidate_resolution.RESOLUTION_HEADERS[:-1]
        self._write_resolution([self._resolution_row()], headers=headers)
        with self.assertRaisesRegex(tool.CategoryMappingValidationError, "header"):
            tool.map_categories(
                resolution_path=self.resolution,
                rules_path=tool.DEFAULT_RULES_PATH,
                output_path=self.output,
                metrics_path=self.metrics,
            )

    def test_25_output_contract_count_set_and_order_match_resolution(self) -> None:
        self._map(
            [
                self._resolution_row("3", categories_tags="en:sodas"),
                self._resolution_row("1", categories_tags="en:breads"),
                self._resolution_row("2", categories_tags=""),
            ]
        )
        with self.output.open("r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            self.assertEqual(reader.fieldnames, tool.CATEGORY_MAPPING_HEADERS)
            rows = list(reader)
        self.assertEqual([row["barcode"] for row in rows], ["1", "2", "3"])
        self.assertEqual(len(rows), 3)

    def test_26_output_validator_enforces_category_contract(self) -> None:
        self._map([self._resolution_row(categories_tags="")])
        row = self._mapping_rows()[0]
        row["cronos_category_candidate"] = "Inventada"
        row["category_mapping_record_sha256"] = catalog_tool.record_hash(
            {
                header: row[header]
                for header in tool.CATEGORY_MAPPING_HEADERS
                if header != "category_mapping_record_sha256"
            }
        )
        with self.output.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=tool.CATEGORY_MAPPING_HEADERS)
            writer.writeheader()
            writer.writerow(row)
        ruleset = tool.load_ruleset(tool.DEFAULT_RULES_PATH, self.categories)
        with self.assertRaisesRegex(tool.CategoryMappingValidationError, "P1.2"):
            tool._validate_mapping_output(
                self.output,
                expected_barcodes={row["barcode"]},
                categories=self.categories,
                ruleset=ruleset,
            )

        row["cronos_category_candidate"] = ""
        row["mapping_reason"] = "exact_curated_tag_rule"
        row["category_mapping_record_sha256"] = catalog_tool.record_hash(
            {
                header: row[header]
                for header in tool.CATEGORY_MAPPING_HEADERS
                if header != "category_mapping_record_sha256"
            }
        )
        with self.output.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=tool.CATEGORY_MAPPING_HEADERS)
            writer.writeheader()
            writer.writerow(row)
        with self.assertRaisesRegex(tool.CategoryMappingValidationError, "incompatible"):
            tool._validate_mapping_output(
                self.output,
                expected_barcodes={row["barcode"]},
                categories=self.categories,
                ruleset=ruleset,
            )

    def test_27_output_and_metrics_are_atomic_on_validation_failure(self) -> None:
        self._write_resolution([self._resolution_row()])
        self.output.write_text("existing-output\n", encoding="utf-8")
        self.metrics.write_text("existing-metrics\n", encoding="utf-8")
        with mock.patch.object(
            tool,
            "_validate_mapping_output",
            side_effect=tool.CategoryMappingValidationError("forced"),
        ):
            with self.assertRaisesRegex(tool.CategoryMappingValidationError, "forced"):
                tool.map_categories(
                    resolution_path=self.resolution,
                    rules_path=tool.DEFAULT_RULES_PATH,
                    output_path=self.output,
                    metrics_path=self.metrics,
                )
        self.assertEqual(self.output.read_text(encoding="utf-8"), "existing-output\n")
        self.assertEqual(self.metrics.read_text(encoding="utf-8"), "existing-metrics\n")

    def test_28_mapping_has_no_network_database_or_uuid_access(self) -> None:
        with (
            mock.patch.object(socket, "socket", side_effect=AssertionError("network used")),
            mock.patch.object(sqlite3, "connect", side_effect=AssertionError("database used")),
            mock.patch.object(uuid, "uuid4", side_effect=AssertionError("uuid used")),
        ):
            metrics = self._map()
        self.assertFalse(metrics["network_access"])
        self.assertFalse(metrics["database_access"])
        self.assertFalse(metrics["uuid_generation"])

    def test_29_cli_human_report_and_metrics_contract(self) -> None:
        rows = [
            self._resolution_row("1", categories_tags="en:breads"),
            self._resolution_row("2", categories_tags="en:groceries"),
            self._resolution_row("3", categories_tags="en:alcoholic-beverages"),
            self._resolution_row("4", categories_tags=""),
            self._resolution_row("5", categories_tags="en:unknown"),
        ]
        self._write_resolution(rows)
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            exit_code = tool.main(
                [
                    "map",
                    "--resolution",
                    str(self.resolution),
                    "--rules",
                    str(tool.DEFAULT_RULES_PATH),
                    "--output",
                    str(self.output),
                    "--metrics",
                    str(self.metrics),
                ]
            )
        self.assertEqual(exit_code, 0)
        report = stdout.getvalue()
        self.assertIn("Category Mapping v1: SUCCESS", report)
        self.assertIn("Mapped:\n  Alimentos: 1", report)
        metrics = json.loads(self.metrics.read_text(encoding="utf-8"))
        expected = {
            "resolution_rows_total": 5,
            "mapping_rows_total": 5,
            "with_category_evidence": 4,
            "without_category_evidence": 1,
            "mapped": 1,
            "review": 1,
            "excluded": 1,
            "unresolved": 2,
            "unresolved_no_category_evidence": 1,
            "unresolved_no_matching_rule": 1,
            "review_required": 1,
            "review_ambiguous_target": 0,
            "excluded_out_of_scope": 1,
            "rules_total": 9,
            "rules_map": 7,
            "rules_review": 1,
            "rules_exclude": 1,
            "mapped_by_exact_main_category": 0,
            "mapped_by_general_tag_rule": 1,
            "mapped_alimentos": 1,
            "mapped_bebidas": 0,
            "mapped_snacks_y_confiteria": 0,
            "mapped_aseo_del_hogar": 0,
            "mapped_cuidado_personal": 0,
            "network_access": False,
            "database_access": False,
            "uuid_generation": False,
        }
        for key, value in expected.items():
            self.assertEqual(metrics[key], value, key)

    def test_30_matcher_schema_requires_one_valid_non_empty_matcher(self) -> None:
        invalid_rules = [
            {
                "rule_id": "missing-matchers",
                "action": "map",
                "target_category": "Alimentos",
                "reason": "test",
            },
            self._rule("empty-matchers", tags=[], main_tags=[]),
            {
                **self._rule("bad-main-type"),
                "match_main_category_any": "en:spaghetti",
            },
            {**self._rule("bad-tags-type"), "match_tags_any": "en:breads"},
            self._rule("duplicate-main", tags=[], main_tags=["en:spaghetti", "en:spaghetti"]),
            self._rule("duplicate-tags", tags=["en:breads", "en:breads"], main_tags=[]),
            self._rule("non-string-main", tags=[], main_tags=[42]),  # type: ignore[list-item]
            self._rule("empty-main-tag", tags=[], main_tags=[""]),
        ]
        for rule in invalid_rules:
            with self.subTest(rule_id=rule["rule_id"]):
                self._write_rules([rule])
                with self.assertRaises(tool.CategoryMappingToolError):
                    tool.load_ruleset(self.rules, self.categories)

        for rule in (
            self._rule("main-only", tags=[], main_tags=["en:spaghetti"]),
            self._rule("tags-only", tags=["en:breads"], main_tags=[]),
        ):
            with self.subTest(rule_id=rule["rule_id"]):
                self._write_rules([rule])
                self.assertEqual(len(tool.load_ruleset(self.rules, self.categories).rules), 1)

    def test_31_main_category_matching_is_exact_casefolded_and_trimmed(self) -> None:
        self._map(
            [
                self._resolution_row("1", main_category=" EN:SPAGHETTI ", categories_tags=""),
                self._resolution_row(
                    "2", main_category="en:spaghetti-products", categories_tags=""
                ),
            ]
        )
        rows = {row["barcode"]: row for row in self._mapping_rows()}
        self.assertEqual(rows["1"]["cronos_category_candidate"], "Alimentos")
        self.assertEqual(rows["1"]["mapping_reason"], "exact_main_category_rule")
        self.assertEqual(rows["1"]["matched_off_tags"], "en:spaghetti")
        self.assertEqual(rows["2"]["mapping_status"], "unresolved")

    def test_32_specific_main_category_wins_over_conflicting_ancestor_tags(self) -> None:
        self._map(
            [
                self._resolution_row(
                    "7700304007035",
                    main_category="en:nut-bars",
                    categories_tags="en:breakfast-cereals,en:cereal-bars",
                )
            ]
        )
        row = self._mapping_rows()[0]
        self.assertEqual(row["mapping_status"], "mapped")
        self.assertEqual(row["cronos_category_candidate"], "Snacks y confitería")
        self.assertEqual(row["mapping_reason"], "exact_main_category_rule")
        self.assertEqual(
            row["matched_off_tags"],
            "en:breakfast-cereals|en:cereal-bars|en:nut-bars",
        )

    def test_33_main_map_rules_require_one_unique_target(self) -> None:
        same_target = [
            self._rule("main-a", tags=[], main_tags=["en:specific"]),
            self._rule("main-b", tags=[], main_tags=["en:specific"]),
        ]
        self._map(
            [self._resolution_row(main_category="en:specific", categories_tags="")],
            same_target,
        )
        row = self._mapping_rows()[0]
        self.assertEqual(row["mapping_status"], "mapped")
        self.assertEqual(row["mapping_rule_ids"], "main-a|main-b")

        distinct_targets = [
            same_target[0],
            self._rule(
                "main-drink",
                tags=[],
                main_tags=["en:specific"],
                target="Bebidas",
            ),
        ]
        self._map(
            [self._resolution_row(main_category="en:specific", categories_tags="")],
            distinct_targets,
        )
        row = self._mapping_rows()[0]
        self.assertEqual(row["mapping_status"], "review")
        self.assertEqual(row["mapping_reason"], "ambiguous_target")

    def test_34_exclude_is_absolute_and_review_does_not_block_main_map(self) -> None:
        self._map(
            [
                self._resolution_row(
                    "1",
                    main_category="en:spaghetti",
                    categories_tags="en:groceries",
                ),
                self._resolution_row(
                    "2",
                    main_category="en:spaghetti",
                    categories_tags="en:alcoholic-beverages",
                ),
            ]
        )
        rows = {row["barcode"]: row for row in self._mapping_rows()}
        self.assertEqual(rows["1"]["mapping_status"], "mapped")
        self.assertEqual(rows["1"]["mapping_reason"], "exact_main_category_rule")
        self.assertIn("review-contextual-or-broad-tags", rows["1"]["mapping_rule_ids"])
        self.assertEqual(rows["2"]["mapping_status"], "excluded")

    def test_35_general_tag_fallback_preserves_v1_and_real_ambiguity(self) -> None:
        self._map(
            [
                self._resolution_row("1", main_category="en:unknown", categories_tags="en:sodas"),
                self._resolution_row(
                    "7702535011799",
                    main_category="en:bebidas-bebidas-carbonatadas-sodas-bebidas-de-cola",
                    categories_tags="en:sodas,en:breads",
                ),
            ]
        )
        rows = {row["barcode"]: row for row in self._mapping_rows()}
        self.assertEqual(rows["1"]["cronos_category_candidate"], "Bebidas")
        self.assertEqual(rows["1"]["mapping_reason"], "exact_curated_tag_rule")
        self.assertEqual(rows["7702535011799"]["mapping_status"], "review")
        self.assertEqual(rows["7702535011799"]["mapping_reason"], "ambiguous_target")

    def test_36_main_only_rules_do_not_activate_from_general_tags(self) -> None:
        self._map(
            [
                self._resolution_row("1", main_category="", categories_tags="en:beverages"),
                self._resolution_row("2", main_category="", categories_tags="en:snacks"),
                self._resolution_row("3", main_category="", categories_tags="en:spaghetti"),
            ]
        )
        for row in self._mapping_rows():
            self.assertEqual(row["mapping_status"], "unresolved")

    def test_37_all_v1_1_main_category_additions_map_to_expected_targets(self) -> None:
        additions = {
            "Alimentos": [
                "en:spaghetti", "en:pastas", "en:mayonnaises", "en:peanut-butters",
                "en:margarines", "en:sausages", "en:cornmeal", "en:wheat-flours",
                "en:tomato-sauces", "en:olive-oils", "en:honeys",
                "en:extra-virgin-olive-oils", "en:pancake-mixes", "en:tunas",
                "en:compotes", "en:dried-fruits", "en:oat-flours", "en:coconut-oils",
                "en:tabletop-sweeteners", "en:marmalades", "en:virgin-olive-oils",
                "en:potatoes", "en:canned-sweet-corn", "en:sauces",
            ],
            "Bebidas": [
                "en:beverages", "en:coffees", "en:waters", "en:oat-based-drinks",
                "en:plant-based-milk-alternatives", "en:herbal-teas-in-tea-bags",
                "en:teas", "en:carbonated-waters", "en:colombian-coffees",
                "en:powdered-soy-milks",
            ],
            "Snacks y confitería": [
                "en:snacks", "en:cakes", "en:sweet-snacks", "en:chocolates",
                "en:brownies", "en:dark-chocolates", "en:popcorn",
                "en:milk-chocolates", "en:nut-bars",
            ],
        }
        rows: list[dict[str, str]] = []
        expected: dict[str, str] = {}
        counter = 1
        for target, tags in additions.items():
            for tag in tags:
                barcode = str(counter)
                rows.append(
                    self._resolution_row(barcode, main_category=tag, categories_tags="")
                )
                expected[barcode] = target
                counter += 1
        self._map(rows)
        actual = {row["barcode"]: row for row in self._mapping_rows()}
        self.assertEqual(len(actual), 43)
        for barcode, target in expected.items():
            with self.subTest(barcode=barcode, target=target):
                self.assertEqual(actual[barcode]["cronos_category_candidate"], target)
                self.assertEqual(actual[barcode]["mapping_reason"], "exact_main_category_rule")

    def test_38_protected_broad_or_out_of_scope_main_tags_are_not_mapped(self) -> None:
        protected = [
            "en:milk-jams",
            "en:cereals-and-their-products",
            "en:desserts",
            "en:cocoa-and-hazelnuts-spreads",
            "en:nuts",
            "en:peanuts",
            "en:cocoa-and-chocolate-powders",
            "en:chocolate-powders",
            "en:non-food-products",
            "en:plant-based-foods-and-beverages",
            "en:plant-based-foods",
            "en:cereals-and-potatoes",
            "en:spreads",
            "en:condiments",
            "en:fats",
            "en:fruits-and-vegetables-based-foods",
            "en:vegetable-fats",
            "en:plant-based-spreads",
            "en:breakfasts",
            "en:sweet-spreads",
            "en:meats-and-their-products",
            "en:legumes-and-their-products",
            "en:sweeteners",
            "en:vegetable-oils",
            "en:dried-products",
        ]
        self._map(
            [
                self._resolution_row(str(index), main_category=tag, categories_tags="")
                for index, tag in enumerate(protected, start=1)
            ]
        )
        rows = {row["off_main_category"]: row for row in self._mapping_rows()}
        for tag in protected:
            with self.subTest(tag=tag):
                expected_status = "review" if tag == "en:peanuts" else "unresolved"
                self.assertEqual(rows[tag]["mapping_status"], expected_status)
        self.assertEqual(rows["en:non-food-products"]["mapping_reason"], "no_matching_rule")

    def test_39_ruleset_hash_canonicalizes_both_matchers_and_version(self) -> None:
        rules_a = [
            self._rule(
                "rule-b",
                tags=["en:z", "en:a"],
                main_tags=["en:main-z", "en:main-a"],
            ),
            self._rule("rule-a", tags=["en:b"], main_tags=["en:main-b"]),
        ]
        self._write_rules(rules_a, version="test-1")
        first = tool.load_ruleset(self.rules, self.categories)
        self._write_rules(
            [
                self._rule("rule-a", tags=["en:b"], main_tags=["en:main-b"]),
                self._rule(
                    "rule-b",
                    tags=["en:a", "en:z"],
                    main_tags=["en:main-a", "en:main-z"],
                ),
            ],
            version="test-1",
        )
        reordered = tool.load_ruleset(self.rules, self.categories)
        self.assertEqual(first.ruleset_sha256, reordered.ruleset_sha256)

        self._write_rules(rules_a, version="test-2")
        version_changed = tool.load_ruleset(self.rules, self.categories)
        self.assertNotEqual(first.ruleset_sha256, version_changed.ruleset_sha256)

        self._write_rules(
            [
                self._rule(
                    "rule-b",
                    tags=["en:z", "en:changed-tag"],
                    main_tags=["en:main-z", "en:main-a"],
                ),
                rules_a[1],
            ],
            version="test-1",
        )
        tag_changed = tool.load_ruleset(self.rules, self.categories)
        self.assertNotEqual(first.ruleset_sha256, tag_changed.ruleset_sha256)

        self._write_rules(
            [
                self._rule(
                    "rule-b",
                    tags=["en:z", "en:a"],
                    main_tags=["en:main-z", "en:changed-main"],
                ),
                rules_a[1],
            ],
            version="test-1",
        )
        main_changed = tool.load_ruleset(self.rules, self.categories)
        self.assertNotEqual(first.ruleset_sha256, main_changed.ruleset_sha256)
        shipped = tool.load_ruleset(tool.DEFAULT_RULES_PATH, self.categories)
        self.assertNotEqual(
            shipped.ruleset_sha256,
            "3afcda0283df03c7d64b272d951943d89d4ab2a51823b1543fc4b5e73d682ea2",
        )
        self.assertNotEqual(
            shipped.ruleset_sha256,
            "53e3e5b15162703f1bd02c13343c0eb56b5a97f6b803e69e8896598ba827ac60",
        )

    def test_40_mapping_hash_changes_when_main_precedence_changes_decision(self) -> None:
        row = self._resolution_row(
            main_category="en:specific", categories_tags="en:ancestor"
        )
        self._map(
            [row],
            [
                self._rule("main", tags=[], main_tags=["en:specific"], target="Bebidas"),
                self._rule("ancestor", tags=["en:ancestor"], main_tags=[]),
            ],
        )
        main_decision = self._mapping_rows()[0]
        self._map(
            [row],
            [self._rule("ancestor", tags=["en:ancestor"], main_tags=[])],
        )
        tag_decision = self._mapping_rows()[0]
        self.assertNotEqual(
            main_decision["category_mapping_record_sha256"],
            tag_decision["category_mapping_record_sha256"],
        )
        self.assertEqual(main_decision["mapping_reason"], "exact_main_category_rule")
        self.assertEqual(tag_decision["mapping_reason"], "exact_curated_tag_rule")

    def test_41_all_v1_2_main_category_additions_map_to_expected_targets(self) -> None:
        additions = {
            "Alimentos primary": (
                "Alimentos",
                [
                    "en:durum-wheat-pasta", "en:mixed-vegetable-oils", "en:corn",
                    "en:prepared-meats", "en:hams", "en:meat-analogues",
                    "en:blackberry-jams", "en:powdered-panela", "en:panela-blocks",
                    "en:italian-pasta", "en:fresh-meats", "en:instant-noodle-soups",
                    "en:vinegars", "en:sardines-in-tomato-sauce", "en:mustard-sauces",
                    "en:hummus", "en:pulses", "en:sugar-substitutes",
                    "en:strawberry-jams", "en:jams", "en:barbecue-sauces",
                    "en:balsamic-vinegars-of-modena", "en:canola-oils",
                    "en:liquid-honeys", "en:flours", "en:chicken-sausages",
                    "en:chorizo", "en:canned-peas-and-carrots", "en:mustards",
                    "en:berry-jams", "en:oat", "en:eggs",
                    "en:refined-deodorized-sunflower-oils",
                ],
            ),
            "Alimentos from review": (
                "Alimentos",
                [
                    "en:butters", "en:condensed-milks", "en:salted-margarines",
                    "en:creams", "en:salted-butters", "en:sour-creams",
                    "en:cottage-cheeses", "en:whipped-creams", "en:ghee",
                    "en:petits-suisses", "en:evaporated-milks", "en:salsas-de-chiles",
                ],
            ),
            "Bebidas primary": (
                "Bebidas",
                [
                    "en:mineral-waters", "en:artificially-sweetened-beverages",
                    "en:soy-based-drinks", "en:fruit-based-beverages",
                    "en:orange-juices", "en:tea-bags",
                ],
            ),
            "Bebidas from review": (
                "Bebidas",
                [
                    "en:fermented-milk-drinks", "en:dairy-drinks", "en:kefir",
                    "en:chocolate-milks", "en:flavoured-milks",
                    "en:fruit-and-milk-beverages", "en:instant-beverages",
                ],
            ),
            "Snacks": (
                "Snacks y confitería",
                [
                    "en:chocolate-cakes", "en:biscuits-and-cakes",
                    "en:ice-creams-and-sorbets", "en:milk-chocolate-bar",
                ],
            ),
            "Cuidado personal": ("Cuidado personal", ["es:maquillaje"]),
        }
        rows: list[dict[str, str]] = []
        expected: dict[str, tuple[str, str]] = {}
        counter = 1
        for group, (target, tags) in additions.items():
            for tag in tags:
                barcode = str(counter)
                rows.append(
                    self._resolution_row(barcode, main_category=tag, categories_tags="")
                )
                expected[barcode] = (group, target)
                counter += 1
        self._map(rows)
        actual = {row["barcode"]: row for row in self._mapping_rows()}
        self.assertEqual(len(actual), 63)
        for barcode, (group, target) in expected.items():
            with self.subTest(barcode=barcode, group=group):
                self.assertEqual(actual[barcode]["mapping_status"], "mapped")
                self.assertEqual(actual[barcode]["cronos_category_candidate"], target)
                self.assertEqual(actual[barcode]["mapping_reason"], "exact_main_category_rule")

    def test_42_makeup_is_main_only_and_does_not_map_as_an_ancestor(self) -> None:
        self._map(
            [
                self._resolution_row(
                    "1", main_category="es:maquillaje", categories_tags="en:non-food-products"
                ),
                self._resolution_row(
                    "2", main_category="en:unknown", categories_tags="es:maquillaje"
                ),
            ]
        )
        rows = {row["barcode"]: row for row in self._mapping_rows()}
        self.assertEqual(rows["1"]["cronos_category_candidate"], "Cuidado personal")
        self.assertEqual(rows["1"]["mapping_reason"], "exact_main_category_rule")
        self.assertEqual(rows["2"]["mapping_status"], "unresolved")

    def test_43_specific_dairy_main_category_wins_over_generic_review(self) -> None:
        self._map(
            [
                self._resolution_row(
                    "1", main_category="en:butters", categories_tags="en:dairies"
                ),
                self._resolution_row(
                    "2", main_category="en:kefir", categories_tags="en:dairies"
                ),
            ]
        )
        rows = {row["barcode"]: row for row in self._mapping_rows()}
        self.assertEqual(rows["1"]["cronos_category_candidate"], "Alimentos")
        self.assertEqual(rows["2"]["cronos_category_candidate"], "Bebidas")
        for row in rows.values():
            self.assertEqual(row["mapping_reason"], "exact_main_category_rule")
            self.assertIn("review-contextual-or-broad-tags", row["mapping_rule_ids"])

    def test_44_protected_v1_2_categories_keep_existing_non_mapped_semantics(self) -> None:
        unresolved = [
            "en:nuts", "en:cocoa-and-chocolate-powders", "en:chocolate-powders",
            "en:cereals-and-their-products", "en:non-food-products", "en:milk-jams",
            "en:desserts", "en:cocoa-and-hazelnuts-spreads", "en:cocoa-powders",
            "en:fats", "en:mixed-nuts", "en:sweeteners",
            "en:coconut-milks-and-creams", "fr:pates-a-tartiner",
        ]
        review = ["en:groceries", "en:dairies", "en:peanuts", "en:jelly-desserts"]
        tags = unresolved + review
        self._map(
            [
                self._resolution_row(str(index), main_category=tag, categories_tags="")
                for index, tag in enumerate(tags, start=1)
            ]
        )
        rows = {row["off_main_category"]: row for row in self._mapping_rows()}
        for tag in unresolved:
            with self.subTest(tag=tag):
                self.assertEqual(rows[tag]["mapping_status"], "unresolved")
                self.assertEqual(rows[tag]["mapping_reason"], "no_matching_rule")
        for tag in review:
            with self.subTest(tag=tag):
                self.assertEqual(rows[tag]["mapping_status"], "review")
                self.assertEqual(rows[tag]["mapping_reason"], "review_required")

    def test_45_v1_2_additions_are_main_only_and_do_not_target_household(self) -> None:
        ruleset = tool.load_ruleset(tool.DEFAULT_RULES_PATH, self.categories)
        main_only_rules = [
            rule
            for rule in ruleset.rules
            if rule.rule_id.startswith("map-main-")
        ]
        all_general_tags = {
            tag for rule in ruleset.rules for tag in rule.match_tags_any
        }
        v1_2_new_tags = {
            "en:durum-wheat-pasta", "en:mineral-waters", "en:chocolate-cakes",
            "es:maquillaje", "en:butters", "en:kefir", "en:flours",
        }
        self.assertTrue(v1_2_new_tags.isdisjoint(all_general_tags))
        self.assertTrue(all(not rule.match_tags_any for rule in main_only_rules))
        self.assertTrue(
            all(rule.target_category != "Aseo del hogar" for rule in ruleset.rules)
        )


if __name__ == "__main__":
    unittest.main()
