#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
CHECK_DIR=$(mktemp -d)
trap 'rm -rf "$CHECK_DIR"' EXIT
python3 - "$CHECK_DIR" <<'PY'
from pathlib import Path
import sys
source=Path('Sources/TimeMaster.swift').read_text().split('@MainActor final class Store')[0]
Path(sys.argv[1],'Checks.swift').write_text(source+Path("Sources/CardGeometry.swift").read_text()+Path("Sources/GroupModel.swift").read_text()+Path('Tests/TimeModelChecks.swift').read_text())
PY
xcrun swiftc -parse-as-library -swift-version 5 "$CHECK_DIR/Checks.swift" -o "$CHECK_DIR/checks" -framework SwiftUI -framework AppKit
"$CHECK_DIR/checks"
