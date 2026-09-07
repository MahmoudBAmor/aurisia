from __future__ import annotations

import unittest
from pathlib import Path

from aurisia.language import ArabicScriptNormalizer


class ArabicScriptNormalizerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.normalizer = ArabicScriptNormalizer.from_yaml(
            Path("language_packs/aeb-TN/lexicon.yaml")
        )

    def test_known_code_switched_phrases_are_rendered_in_arabic(self) -> None:
        result = self.normalizer.normalize("نحب نعمل rendez-vous و mise à jour في téléphone")

        self.assertEqual(result, "نحب نعمل رونديفو و ميزاجور في تليفون")

    def test_unknown_latin_terms_are_preserved(self) -> None:
        result = self.normalizer.normalize("نستعمل Aurisia كل يوم")

        self.assertEqual(result, "نستعمل Aurisia كل يوم")

    def test_observed_tunisian_code_switches_follow_arabic_display_policy(self) -> None:
        result = self.normalizer.normalize(
            "امشي لل pharmacie واعمل marche arrière ونظف el lavabo"
        )

        self.assertEqual(
            result,
            "امشي لل فارماسي واعمل مارش أريار ونظف el لافابو",
        )


if __name__ == "__main__":
    unittest.main()
