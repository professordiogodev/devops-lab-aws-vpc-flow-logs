#!/usr/bin/env bash
# Deletes the servers, the network, your flow log, the log group and the role. Run with: ./teardown.sh
set -u
aws sts get-caller-identity >/dev/null 2>&1 || { echo "No working AWS credentials." >&2; exit 1; }
L=aws-vpc-flow-logs
IDS=$(aws ec2 describe-instances --filters Name=tag:lab,Values=$L Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId' --output text)
[ -n "$IDS" ] && aws ec2 terminate-instances --instance-ids $IDS >/dev/null && aws ec2 wait instance-terminated --instance-ids $IDS && echo "terminated $IDS"
# flow logs on the lab VPC, and the log groups and roles they use
for V in $(aws ec2 describe-vpcs --filters Name=tag:lab,Values=$L --query 'Vpcs[].VpcId' --output text); do
  for F in $(aws ec2 describe-flow-logs --filter Name=resource-id,Values=$V --query 'FlowLogs[].FlowLogId' --output text); do
    aws ec2 delete-flow-logs --flow-log-ids $F >/dev/null && echo "deleted flow log $F"
  done
done
for G in $(aws logs describe-log-groups --log-group-name-prefix /clippy/flowlab --query 'logGroups[].logGroupName' --output text); do
  aws logs delete-log-group --log-group-name "$G" && echo "deleted log group $G"
done
for R in $(aws iam list-roles --path-prefix / --query "Roles[?starts_with(RoleName, 'clippy-flowlab')].RoleName" --output text); do
  for i in $(aws iam list-instance-profiles-for-role --role-name "$R" --query 'InstanceProfiles[].InstanceProfileName' --output text); do aws iam remove-role-from-instance-profile --instance-profile-name $i --role-name "$R"; aws iam delete-instance-profile --instance-profile-name $i; done
  for p in $(aws iam list-role-policies --role-name "$R" --query 'PolicyNames' --output text); do aws iam delete-role-policy --role-name "$R" --policy-name $p; done
  for p in $(aws iam list-attached-role-policies --role-name "$R" --query 'AttachedPolicies[].PolicyArn' --output text); do aws iam detach-role-policy --role-name "$R" --policy-arn $p; done
  aws iam delete-role --role-name "$R" && echo "deleted role $R"
done
for V in $(aws ec2 describe-vpcs --filters Name=tag:lab,Values=$L --query 'Vpcs[].VpcId' --output text); do
  E=$(aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$V --query 'VpcEndpoints[].VpcEndpointId' --output text)
  if [ -n "$E" ]; then
    aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $E >/dev/null 2>&1 && echo "deleting VPC endpoint(s) $E (this can take a few minutes)"
    for _ in $(seq 1 30); do [ -z "$(aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$V --query 'VpcEndpoints[?State!=`deleted`].VpcEndpointId' --output text)" ] && break; sleep 10; done
  fi
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    for g in $(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$V --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text); do aws ec2 delete-security-group --group-id $g >/dev/null 2>&1; done
    for a in $(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$V --query 'RouteTables[].Associations[?!Main].RouteTableAssociationId' --output text); do aws ec2 disassociate-route-table --association-id $a >/dev/null 2>&1; done
    for r in $(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$V --query 'RouteTables[?length(Associations[?Main])==`0`].RouteTableId' --output text); do aws ec2 delete-route-table --route-table-id $r >/dev/null 2>&1; done
    for s in $(aws ec2 describe-subnets --filters Name=vpc-id,Values=$V --query 'Subnets[].SubnetId' --output text); do aws ec2 delete-subnet --subnet-id $s >/dev/null 2>&1; done
    for g in $(aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=$V --query 'InternetGateways[].InternetGatewayId' --output text); do aws ec2 detach-internet-gateway --internet-gateway-id $g --vpc-id $V >/dev/null 2>&1; aws ec2 delete-internet-gateway --internet-gateway-id $g >/dev/null 2>&1; done
    aws ec2 delete-vpc --vpc-id $V >/dev/null 2>&1 && { echo "deleted VPC $V"; break; }
    sleep 20
  done
done
r=clippy-flowlab-client
aws iam remove-role-from-instance-profile --instance-profile-name $r --role-name $r 2>/dev/null
aws iam delete-instance-profile --instance-profile-name $r 2>/dev/null
echo "Now run ./verify-teardown.sh"
