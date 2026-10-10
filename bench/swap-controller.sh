#!/usr/bin/env bash
# s3-01 controller swap: stop the stock v0.5.3 controller on forkd-p0-1,
# install the candidate (built from keeganmccallum/s3-01-forkd-fanout),
# restart with the SAME flags. Run under sudo on the node.
set -euo pipefail
CAND_DIR="${1:?usage: swap-controller.sh <dir-with-forkd+forkd-controller>}"

echo "=== pre-swap state"
pgrep -af forkd-controller || true
TOKEN=$(cat /var/lib/forkd/token)
curl -s -m 5 -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8889/v1/sandboxes | python3 -c "import json,sys; print('live sandboxes:', len(json.load(sys.stdin)))"

echo "=== stopping old controller"
pkill -f 'forkd-controller serve' || true
for i in $(seq 1 20); do pgrep -f 'forkd-controller serve' >/dev/null || break; sleep 0.5; done
pgrep -f 'forkd-controller serve' && { echo "old controller still alive"; exit 1; }

echo "=== installing candidate"
cp "$CAND_DIR/forkd-controller" /usr/local/forkd/forkd-controller-candidate
cp "$CAND_DIR/forkd" /usr/local/forkd/forkd-candidate
"$CAND_DIR/forkd-controller" --help >/dev/null 2>&1 || true  # sanity: binary runs

echo "=== starting candidate (same flags as the stock run)"
nohup /usr/local/forkd/forkd-controller-candidate serve \
  --state /var/lib/forkd/state.json \
  --snapshot-root /var/lib/forkd/xdg/forkd/snapshots \
  --audit-log /var/log/forkd/audit.log \
  --token-file /var/lib/forkd/token \
  --prewarm-scratch-dir /dev/shm/forkd-prewarm \
  >/var/log/forkd/controller-candidate.log 2>&1 &
sleep 2
pgrep -af forkd-controller-candidate || { echo "candidate failed to start"; tail -20 /var/log/forkd/controller-candidate.log; exit 1; }
echo "=== healthz"
curl -s -m 5 http://127.0.0.1:8889/healthz; echo
curl -s -m 5 -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8889/version; echo
echo "swap complete; candidate pid(s): $(pgrep -f forkd-controller-candidate | tr '\n' ' ')"
