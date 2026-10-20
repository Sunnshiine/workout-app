#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["numpy"]
# ///
"""uv run .agents/skills/verify/tests/test_motion.py      (needs ffmpeg and ffprobe on PATH)"""
import unittest

from test_motion_clips import *  # noqa: F401,F403
from test_motion_summarize import *  # noqa: F401,F403
from test_motion_steps import *  # noqa: F401,F403
from test_motion_takes import *  # noqa: F401,F403
from test_motion_verdicts import *  # noqa: F401,F403

if __name__ == "__main__":
    unittest.main()
