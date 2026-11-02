"""Host fixtures for dependencyInsight parsing; no Gradle or Android execution."""
from pathlib import Path
import unittest
from unittest.mock import patch

from ci_build_trial import BuildError, NATIVE, resolved_native, selected_native_version


class NativeDependencyReceiptTests(unittest.TestCase):
    module = "posthog-android"
    coordinate = "com.posthog:posthog-android:"

    def test_resolved_heading_and_strict_lock_selection(self):
        output = """> Task :app:dependencyInsight
com.posthog:posthog-android:3.75.0
  Variant releaseRuntimeElements-published:
  Selection reasons:
    - By constraint: dependency was locked to version '3.75.0'

com.posthog:posthog-android:{strictly 3.75.0} -> 3.75.0
\\--- debugRuntimeClasspath

com.posthog:posthog-android:3.75.0
+--- debugRuntimeClasspath
\\--- project :posthog_flutter
BUILD SUCCESSFUL in 2s
"""
        self.assertEqual(selected_native_version(output, self.module), "3.75.0")

    def test_strict_request_without_arrow_does_not_corrupt_heading(self):
        output = self.coordinate + "3.75.0\n" + self.coordinate + "{strictly 3.75.0} (c)\n"
        self.assertEqual(selected_native_version(output, self.module), "3.75.0")

    def test_range_request_resolved_to_pin_is_accepted(self):
        output = self.coordinate + "3.75.0\n" + self.coordinate + "[3.70,4.0) -> 3.75.0 (*)\n"
        self.assertEqual(selected_native_version(output, self.module), "3.75.0")

    def test_constraint_or_arrow_without_resolved_heading_is_not_attestation(self):
        for expression in ("{strictly 3.75.0}", "{strictly 3.75.0} -> 3.75.0", "3.74.0 -> 3.75.0"):
            with self.subTest(expression=expression), self.assertRaises(BuildError):
                selected_native_version(self.coordinate + expression, self.module)

    def test_mixed_selected_versions_fail(self):
        output = self.coordinate + "3.75.0\n" + self.coordinate + "{strictly 3.75.0} -> 3.76.0\n"
        with self.assertRaises(BuildError):
            selected_native_version(output, self.module)

    def test_missing_failed_or_unrecognized_output_cannot_pass(self):
        for output in ("", self.coordinate + "3.75.0 FAILED\n",
                       self.coordinate + "3.75.0\nFAILED to resolve another dependency",
                       self.coordinate + "3.75.0\n" + self.coordinate + "unknown-format",
                       "com.posthog:posthog:6.48.0\n"):
            with self.subTest(output=output), self.assertRaises(BuildError):
                selected_native_version(output, self.module)

    def test_both_actual_pins_are_required(self):
        fixtures = [f"com.posthog:{module}:{version}\n"
                    f"com.posthog:{module}:{{strictly {version}}} -> {version}\n"
                    for module, version in NATIVE.items()]
        with patch("ci_build_trial.run", side_effect=fixtures):
            self.assertEqual(resolved_native(Path("/unused"), {}), NATIVE)

    def test_consistently_upgraded_component_is_rejected(self):
        output = self.coordinate + "3.76.0\n" + self.coordinate + "{strictly 3.75.0} -> 3.76.0\n"
        with patch("ci_build_trial.run", return_value=output), self.assertRaises(BuildError):
            resolved_native(Path("/unused"), {})


if __name__ == "__main__":
    unittest.main()
