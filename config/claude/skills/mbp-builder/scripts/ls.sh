#!/bin/bash
# ls.sh: list the b-* builders in the MBP's herdr `builders` session, with status, pane and cwd.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
echo -e "agent\tstatus\tpane\tcwd"
mbb 30 list
