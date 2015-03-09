#!/bin/bash

# This script is meant to be run on the NEW master when we are ready to move the VIP.  This script has the following usage and is currently specific to AWS:
#
#       ./example-ipswitch.sh <vip-cidr>
#
# For example:
#
#       ./example-ipswitch.sh 192.168.24.1/32
#

WRITER_CIDR=$1
ROUTETABLES=$("... get all route tables in VPC ...")
ENIID=$("... get current host's ENI ...")
REGION=$("... get current region ...")
for RTB in $ROUTETABLES; do
	writerRouteExists=$(aws ec2 describe-route-tables --route-table-ids $RTB --region $REGION --filters "Name=route.destination-cidr-block,Values=$WRITER_CIDR" --output text | wc -l)
	if [ "0" == "$writerRouteExists" ]; then
		aws ec2 create-route  --destination-cidr-block $WRITER_CIDR --route-table-id $RTB --network-interface-id $ENIID --region $REGION
	else
		aws ec2 replace-route --destination-cidr-block $WRITER_CIDR --route-table-id $RTB --network-interface-id $ENIID --region $REGION
	fi
done