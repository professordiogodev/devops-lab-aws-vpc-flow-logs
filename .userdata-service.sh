#!/bin/bash
# Service server: a tiny web service on port 8080.
mkdir -p /srv/clippy && echo clippy-service > /srv/clippy/index.html
cat > /etc/systemd/system/clippy-service.service <<UNIT
[Service]
WorkingDirectory=/srv/clippy
ExecStart=/usr/bin/python3 -m http.server 8080
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload && systemctl enable --now clippy-service
