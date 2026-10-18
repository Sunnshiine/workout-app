#!/usr/bin/env python3
import unittest

from test_evidence_tree import *  # noqa: F401,F403
from test_evidence_tappable import *  # noqa: F401,F403
from test_evidence_tree_commands import *  # noqa: F401,F403
from test_evidence_verify_commands import *  # noqa: F401,F403
from test_evidence_simulator_lock import *  # noqa: F401,F403
from test_evidence_simulator_pick import *  # noqa: F401,F403
from test_evidence_installed import *  # noqa: F401,F403
from test_evidence_app_cache import *  # noqa: F401,F403
from test_evidence_drive_guard import *  # noqa: F401,F403
from test_evidence_capture import *  # noqa: F401,F403
from test_evidence_take import *  # noqa: F401,F403
from test_evidence_record import *  # noqa: F401,F403


if __name__ == "__main__":
    unittest.main()
