#!/bin/sh
# Ship the landing page to the cluster (ns screen-pointer, NodePort 30097 on ubuntu04).
set -e
cd "$(dirname "$0")/.."
{
  cat deploy/app.yaml; echo ---
  python3 - <<'PY'
import base64, json, pathlib
files = {p.name: p.read_text() for p in pathlib.Path('site').glob('*.html')}
files.update({p.name: base64.b64encode(p.read_bytes()).decode() for p in pathlib.Path('site').glob('*.png')})
print(json.dumps({'apiVersion': 'v1', 'kind': 'ConfigMap',
                  'metadata': {'name': 'site', 'namespace': 'screen-pointer'},
                  'data': files}, ensure_ascii=False))
PY
} | ssh ubuntu03 'kubectl apply --server-side --force-conflicts -f - && kubectl -n screen-pointer rollout restart deploy/web && kubectl -n screen-pointer rollout status deploy/web --timeout=120s'
