#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/Web"
python3 - <<'PY'
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
import threading, webbrowser
url = 'http://127.0.0.1:5173'
try:
    server = ThreadingHTTPServer(('127.0.0.1', 5173), SimpleHTTPRequestHandler)
except OSError:
    print('Port 5173 is already in use. If Stickey Notes is running, visit ' + url)
    raise SystemExit(1)
print('Stickey Notes: ' + url + '\nKeep this window open. Press Control-C to stop.')
threading.Timer(0.5, lambda: webbrowser.open(url)).start()
try:
    server.serve_forever()
except KeyboardInterrupt:
    pass
finally:
    server.server_close()
PY
