#!/bin/bash
# Parse-checks audit.sql with the real PostgreSQL grammar. Run it after any edit.
#   pip install pglast   (once)
set -e
python3 - "$(dirname "$0")/audit.sql" <<'PY'
import sys, pglast
sql = open(sys.argv[1]).read()
try:
    n = len(pglast.parse_sql(sql))
except Exception as e:
    print("SYNTAX ERROR:", e); sys.exit(1)
print(f"audit.sql parses cleanly ({n} statement)")
PY
