#!/usr/bin/env python3
"""Source-order regression for context selection vs Design Mode / React Grab.

This is a static ordering check, not a behavioral test: each switching path
awaits page JavaScript, and context selection can arm during that await. The
exclusion call must therefore run again after the last await and before the
other mode becomes active. Native behavior is checked in the tagged app.
"""

from __future__ import annotations

import os
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = Path(os.environ.get("CMUX_CONTEXT_PICKER_SOURCE", ROOT / "Sources/Panels/BrowserPanel+ElementPicker.swift"))


def function_body(text: str, signature: str) -> str:
    start = text.index(signature)
    brace = text.index("{", start)
    depth = 0
    for index in range(brace, len(text)):
        depth += {"{": 1, "}": -1}.get(text[index], 0)
        if depth == 0:
            return text[brace:index]
    raise AssertionError("unbalanced function body")


class ContextModeExclusionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.text = SOURCE.read_text()

    def test_design_mode_enable_stops_context_after_react_grab_await(self) -> None:
        body = function_body(self.text, "func setDesignModeEnabled(")
        enable = body.index("designModeController.setEnabled(enabled")
        await_grab = body.index("await deactivateReactGrabForDesignMode")
        stops = [m.start() for m in re.finditer(r"contextSelectionController\.stop\(\)", body)]
        self.assertTrue(any(await_grab < stop < enable for stop in stops),
                        "context selection must be stopped after React Grab closes and before Design Mode enables")

    def test_react_grab_activation_stops_context_after_design_mode_await(self) -> None:
        body = function_body(self.text, "func prepareForReactGrabActivation(")
        await_design = body.index("await designModeController.setEnabled")
        result = body.index("return disabled")
        stops = [m.start() for m in re.finditer(r"contextSelectionController\.stop\(\)", body)]
        self.assertTrue(any(await_design < stop < result for stop in stops),
                        "context selection must be stopped after Design Mode closes and before React Grab activates")


if __name__ == "__main__":
    unittest.main()
