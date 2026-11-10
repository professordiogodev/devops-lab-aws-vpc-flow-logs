#!/usr/bin/env bash
# Proves the lab left nothing in AWS. Run with: ./verify-teardown.sh
set -u
ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || { echo "No working AWS credentials." >&2; exit 1; }
echo "Checking account $ACCOUNT, region $(aws configure get region)"
pass=0; failn=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS  $d"; pass=$((pass+1)); else echo "FAIL  $d"; failn=$((failn+1)); fi; }
empty() { local r; r=$(eval "$1" 2>/dev/null); [ -z "$r" ] || [ "$r" = None ]; }
L=aws-vpc-flow-logs
T="Name=tag:lab,Values=$L"
check "no running or stopped server tagged lab=$L" empty "aws ec2 describe-instances --filters $T Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId' --output text"
check "no VPC tagged lab=$L" empty "aws ec2 describe-vpcs --filters $T --query 'Vpcs[].VpcId' --output text"
check "no log group starting with /clippy/flowlab" empty "aws logs describe-log-groups --log-group-name-prefix /clippy/flowlab --query 'logGroups[].logGroupName' --output text"
check "no IAM role whose name starts with clippy-flowlab" empty "aws iam list-roles --query \"Roles[?starts_with(RoleName, 'clippy-flowlab')].RoleName\" --output text"
check "no instance profile clippy-flowlab-client" bash -c "! aws iam get-instance-profile --instance-profile-name clippy-flowlab-client"
echo
if [ "$failn" -eq 0 ]; then echo "TEARDOWN VERIFIED ($pass/$pass) in account $ACCOUNT"; else echo "NOT CLEAN: $failn leftover(s). Remove them and run this again."; fi
exit "$failn"
