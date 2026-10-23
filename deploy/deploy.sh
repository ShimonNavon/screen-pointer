#!/bin/sh
# Publish the website and public demonstration assets on the Kubernetes cluster.
set -e
cd "$(dirname "$0")/.."
ssh ubuntu03 'kubectl apply -f -' < deploy/app.yaml
ssh ubuntu03 'kubectl -n screen-pointer rollout status deploy/web --timeout=120s'
COPYFILE_DISABLE=1 tar -cf - -C site/media . | ssh ubuntu03 'kubectl -n screen-pointer exec -i deploy/web -- tar -xf - -C /usr/share/nginx/html/media'
python3 - <<'PY' | ssh ubuntu03 'kubectl apply --server-side --force-conflicts -f -'
import json,pathlib
print(json.dumps({'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':'site','namespace':'screen-pointer'},'data':{p.name:p.read_text() for p in pathlib.Path('site').glob('*.html')}}))
PY
ssh ubuntu03 'kubectl -n screen-pointer rollout restart deploy/web && kubectl -n screen-pointer rollout status deploy/web --timeout=120s'
