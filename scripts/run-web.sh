#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}/Web"
print 'Stickey Notes is available at http://127.0.0.1:5173'
print 'Press Control-C to stop the local server.'
python3 -m http.server 5173 --bind 127.0.0.1
