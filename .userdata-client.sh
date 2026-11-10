#!/bin/bash
# Client server: every 15 seconds call the service on port 8080 and write the result on its own tags (call = ok or fail).
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get install -y python3-boto3
cat > /usr/local/bin/probe.py <<'PY'
import time, urllib.request, boto3
TOKEN = urllib.request.urlopen(urllib.request.Request("http://169.254.169.254/latest/api/token", method="PUT", headers={"X-aws-ec2-metadata-token-ttl-seconds": "600"})).read().decode()
def meta(p):
    return urllib.request.urlopen(urllib.request.Request("http://169.254.169.254/latest/meta-data/" + p, headers={"X-aws-ec2-metadata-token": TOKEN})).read().decode()
iid, region = meta("instance-id"), meta("placement/region")
ec2 = boto3.client("ec2", region_name=region)
while True:
    try:
        ok = urllib.request.urlopen("http://10.50.1.20:8080/", timeout=3).read().decode().strip() == "clippy-service"
    except Exception:
        ok = False
    ec2.create_tags(Resources=[iid], Tags=[{"Key": "call", "Value": "ok" if ok else "fail"}, {"Key": "call-checked", "Value": time.strftime("%H:%M:%S")}])
    time.sleep(15)
PY
cat > /etc/systemd/system/probe.service <<UNIT
[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/probe.py
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload && systemctl enable --now probe
