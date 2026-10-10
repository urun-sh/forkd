#!/usr/bin/env bash
# s3-01 fan-out bench: run AFTER the candidate controller is up.
# Usage: sudo bash fanout-bench.sh [n]
set -euo pipefail
N="${1:-10}"
TOKEN=$(cat /var/lib/forkd/token)
BASE=http://127.0.0.1:8889

echo "=== GET /healthz"; curl -s -m 5 "$BASE/healthz"; echo
echo "=== POST /v1/sandboxes n=$N (per_child_netns ABSENT — the fix under test)"
T0=$(date +%s%3N)
RESP=$(curl -s -m 120 -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"snapshot_tag\":\"envd-base\",\"n\":$N}" "$BASE/v1/sandboxes")
T1=$(date +%s%3N)
echo "wall_ms=$((T1-T0))"
echo "$RESP" | python3 -c "
import json,sys
d=json.load(sys.stdin)
if isinstance(d, dict):
    print('ERROR:', json.dumps(d)[:300]); sys.exit(1)
print('spawned:', len(d))
print('netns:', sorted(s['netns'] for s in d))
for s in d[:2]: print(s['id'], s['netns'], s['pid'])
"
IDS=$(echo "$RESP" | python3 -c "
import json,sys
d=json.load(sys.stdin)
if isinstance(d, dict): sys.exit(1)
print(' '.join(s['id'] for s in d))
")
echo "=== cleanup (mine only)"
for id in $IDS; do curl -s -m 30 -X DELETE -H "Authorization: Bearer $TOKEN" "$BASE/v1/sandboxes/$id" -o /dev/null -w "del:%{http_code} "; done; echo
echo "=== live count after cleanup:"
curl -s -m 5 -H "Authorization: Bearer $TOKEN" "$BASE/v1/sandboxes" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))"
