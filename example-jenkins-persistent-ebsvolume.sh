#!/bin/bash

PROFILE_NAME=myawscliprofilename
REGION='us-west-2'
AVAILABILITY_ZONE="${region}a"
TAG1VAL=tag1value
TAG2VAL=tag2value

numVolumes=$(aws ec2 describe-volumes --filters "Name=tag:Tag1,Values=$TAG1VAL" "Name=tag:Tag2,Values=$TAG2VAL" --query "Volumes[*].VolumeId" --output text --profile $PROFILE_NAME --region $REGION | wc -w)

if [ $numVolumes -eq 0 ]; then
    echo "No volume found. Creating new volume..."
    # 
    # !!! IMPORTANT !!!
    # Note the --encrypted flag
    #
    volumeId=$(aws ec2 create-volume --profile $PROFILE_NAME --size 201 --availability-zone $AVAILABILITY_ZONE --region $REGION --encrypted | grep "VolumeId" | awk -F\" '{print $4}')
    echo "Created volume ${volumeId}..."

    echo ""
    echo "Tagging volume appropriately so that it can be found by the jenkins bootstrap..."
    tagResult=$(aws ec2 create-tags --resources $volumeId --tags "Key=Tag1,Value=$TAG1VAL" "Key=Tag2,Value=$TAG2VAL" --profile $PROFILE_NAME --region $REGION --output text)
    if [ "$tagResult" == "true" ]; then
        echo "Successfully tagged volume"
    fi

    echo ""
    echo "Waiting until volume is ready for use..."
    status=$(aws ec2 describe-volume-status --volume-ids $volumeId --query "VolumeStatuses[0].VolumeStatus.Status" --profile $PROFILE_NAME --region $REGION | awk -F\" '{print $2}')
    nextWait=0
    until [ "$status" == "ok" ] || [ $nextWait -ge 20 ]; do
        echo "Not ready yet. Sleeping for $nextWait seconds..."
        sleep $(( nextWait++ ))
        status=$(aws ec2 describe-volume-status --volume-ids $volumeId --query "VolumeStatuses[0].VolumeStatus.Status" --profile $PROFILE_NAME --region $REGION | awk -F\" '{print $2}')
    done
    echo "Volume status: $status"
else
    echo "Found existing volume with matching tags.  No need to create a volume."
fi
