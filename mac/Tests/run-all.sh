#!/bin/bash
# Run from the repository root. Never launches Pip Voice or touches live input.
set -euo pipefail
bash mac/Tests/run-audio-regressions.sh
bash mac/Tests/run-clipboard-regressions.sh
bash mac/Tests/run-keyboard-regressions.sh
bash mac/Tests/run-gesture-regressions.sh
bash mac/Tests/run-vocabulary-regressions.sh

bash mac/Tests/verify-package.sh "${PIP_VOICE_TEST_BUNDLE:-mac/build/Pip Voice.app}"

bash mac/Tests/run-ownership-regressions.sh

bash mac/Tests/run-coordinator-regressions.sh
