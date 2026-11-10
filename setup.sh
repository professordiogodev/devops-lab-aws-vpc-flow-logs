#!/usr/bin/env bash
# Builds one VPC with two servers. Run once: ./setup.sh
#   client   10.50.1.10   calls http://10.50.1.20:8080/ every 15 seconds and writes the result on ITS OWN tags (call = ok or fail)
#   service  10.50.1.20   a tiny web service on port 8080
# Somebody wrote the service's firewall in a hurry.
set -u
cd "$(dirname "$0")"
aws sts get-caller-identity >/dev/null 2>&1 || { echo "No working AWS credentials." >&2; exit 1; }
L=aws-vpc-flow-logs
if aws ec2 describe-vpcs --filters Name=tag:lab,Values=$L --query 'Vpcs[].VpcId' --output text | grep -q vpc-; then echo "The network already exists."; exit 0; fi
tags() { echo "ResourceType=$1,Tags=[{Key=lab,Value=$L},{Key=Name,Value=$2}]"; }
AMI=$(aws ssm get-parameter --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id --query Parameter.Value --output text)
AZ=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0].ZoneName' --output text)
# the role lets the client tag itself, nothing else
aws iam create-role --role-name clippy-flowlab-client --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' --tags Key=lab,Value=$L >/dev/null
aws iam put-role-policy --role-name clippy-flowlab-client --policy-name tag-myself --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"ec2:CreateTags","Resource":"arn:aws:ec2:*:*:instance/*","Condition":{"StringEquals":{"ec2:ResourceTag/lab":"aws-vpc-flow-logs"}}}]}'
aws iam create-instance-profile --instance-profile-name clippy-flowlab-client >/dev/null
aws iam add-role-to-instance-profile --instance-profile-name clippy-flowlab-client --role-name clippy-flowlab-client
V=$(aws ec2 create-vpc --cidr-block 10.50.0.0/16 --tag-specifications "$(tags vpc flowlab)" --query Vpc.VpcId --output text)
aws ec2 modify-vpc-attribute --vpc-id $V --enable-dns-hostnames
G=$(aws ec2 create-internet-gateway --tag-specifications "$(tags internet-gateway flowlab)" --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $G --vpc-id $V
SN=$(aws ec2 create-subnet --vpc-id $V --cidr-block 10.50.1.0/24 --availability-zone $AZ --tag-specifications "$(tags subnet flowlab)" --query Subnet.SubnetId --output text)
aws ec2 modify-subnet-attribute --subnet-id $SN --map-public-ip-on-launch
RT=$(aws ec2 create-route-table --vpc-id $V --tag-specifications "$(tags route-table flowlab)" --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id $RT --destination-cidr-block 0.0.0.0/0 --gateway-id $G >/dev/null
aws ec2 associate-route-table --route-table-id $RT --subnet-id $SN >/dev/null
CSG=$(aws ec2 create-security-group --group-name flowlab-client --description "client" --vpc-id $V --tag-specifications "$(tags security-group flowlab-client)" --query GroupId --output text)
SSG=$(aws ec2 create-security-group --group-name flowlab-service --description "service" --vpc-id $V --tag-specifications "$(tags security-group flowlab-service)" --query GroupId --output text)
# the hurried rule: the service listens on 8080 and the firewall opens 8081
aws ec2 authorize-security-group-ingress --group-id $SSG --protocol tcp --port 8081 --source-group $CSG >/dev/null
sleep 5
SID=$(aws ec2 run-instances --image-id $AMI --instance-type t3.micro --subnet-id $SN --private-ip-address 10.50.1.20 --security-group-ids $SSG \
  --user-data file://.userdata-service.sh --metadata-options HttpTokens=required,HttpEndpoint=enabled \
  --tag-specifications "$(tags instance flowlab-service)" --query 'Instances[0].InstanceId' --output text)
CID=$(aws ec2 run-instances --image-id $AMI --instance-type t3.micro --subnet-id $SN --private-ip-address 10.50.1.10 --security-group-ids $CSG \
  --iam-instance-profile Name=clippy-flowlab-client --user-data file://.userdata-client.sh --metadata-options HttpTokens=required,HttpEndpoint=enabled \
  --tag-specifications "$(tags instance flowlab-client)" --query 'Instances[0].InstanceId' --output text)
echo "One VPC ($V), two servers:"
echo "  client   $CID  10.50.1.10   calls the service every 15 seconds"
echo "  service  $SID  10.50.1.20   listens on port 8080"
echo "In about two minutes the client starts writing the tag call=ok or call=fail on itself."
