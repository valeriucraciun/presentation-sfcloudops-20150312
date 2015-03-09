#!/bin/bash

REGION=us-west-2
TAG1VAL=tag1value
TAG2VAL=tag2value
INSTANCE_ID=$(curl -sL 169.254.169.254/latest/meta-data/instance-id)

# Increase root filesystem to it's max capacity
resize2fs /dev/sda1

# Find and attach to the volume that we already know exists
volumeId=$(aws ec2 describe-volumes --filters "Name=tag:Tag1,Values=$TAG1VAL" "Name=tag:Tag2,Values=$TAG2VAL" --query "Volumes[*].VolumeId" --output text --region $REGION)
aws ec2 attach-volume --device /dev/xvdj --volume-id $volumeId --instance-id $INSTANCE_ID --region $REGION

# Give it a sec to actually attach...
nextWait=0
test -e /dev/xvdj
until [ $? -eq 0 ] || [ $nextWait -ge 20 ]; do
    echo "Not ready yet. Sleeping for $nextWait seconds..."
    sleep $(( nextWait++ ))
    test -e /dev/xvdj
done

mkdir -p /var/lib/jenkins

# Create the filesystem if the disk has never been formatted before",
file -sL /dev/xvdj | grep ext4 || { mkfs -t ext4 /dev/xvdj; }

# Make the mount permanent by putting into fstab
echo "/dev/xvdj /var/lib/jenkins auto noatime 0 0" >> /etc/fstab
mount -a

# Give jenkins some swap space
test -e /var/swap.1 || {
    sudo /bin/dd if=/dev/zero of=/var/swap.1 bs=1M count=1024;
    sudo /sbin/mkswap /var/swap.1;
    sudo /sbin/swapon /var/swap.1;
    sudo echo "/var/swap.1 swap swap defaults 0 0" >> /etc/fstab
}

# Now install and configure jenkins at it's default location in /var/lib/jenkins
# If your instance ever dies and gets recreated (b/c it is in an auto-scale group) 
# it should re-run this script to re-attach to that volume. 