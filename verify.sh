#!/usr/bin/env bash
# Reads the flow log, the logs it delivered, the firewall and what the client says. Run with: ./verify.sh
cd "$(dirname "$0")" || exit 1
aws sts get-caller-identity >/dev/null 2>&1 || { echo "No working AWS credentials." >&2; exit 1; }
exec python3 .lab/awscheck.py
