"""Test package for the Ralph Python orchestrator.

Ensures the repository root is importable so tests can ``import ralph.orchestrator``
regardless of how the suite is invoked.
"""

from __future__ import annotations

import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))
