#!/bin/bash

EBS_VOLUME_TYPE="gp2"            # Valid values: standard, gp2, io1
ENCRYPTED_EBS_VOLUME_SIZE="20"   # in GB
INSTANCE_ID=$(curl -sL 169.254.169.254/latest/meta-data/instance-id)
AVAILABILITY_ZONE=$(curl -sL 169.254.169.254/latest/meta-data/placement/availability-zone)
REGION="${AVAILABILITY_ZONE%?}"  # just remove last char

## no need to run this script if we already have xvdf mounted
if ! df -h | grep -q xvdf; then

    ## we need python-pip
    yum install -y python-pip

    ## only the latest awscli has the encrypted ebs volume support
    pip install --upgrade awscli

    ## get our root volume ID
    ROOT_VOLUME_ID="$(aws --region $REGION ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].BlockDeviceMappings[0]" | grep VolumeId | awk -F'\"' '{print $4}')"

    ## go get all the existing tags and store them in a temp file
    tmp_tag_file="$(mktemp)"
    aws --region $REGION ec2 describe-tags --filter Name=resource-id,Values=$ROOT_VOLUME_ID --query 'Tags[*].{Key:Key,Value:Value}' | perl -pe 's{\\s}{}g' > $tmp_tag_file

    # Enable SSD EBS volumes by setting the environment variable EBS_VOLUME_TYPE to gp2 or io1.  Defaults to standard
    # EBS volume type if no env variable is set.
    EBS_VOLUME_TYPE=${EBS_VOLUME_TYPE:-standard}
    found_valid_ebs_type=0
    for VALID_VOLUME_TYPE in standard gp2 io1 ; do
      if [ "$EBS_VOLUME_TYPE" == "$VALID_VOLUME_TYPE" ] ; then
        echo "Found valid type $VALID_VOLUME_TYPE"
        found_valid_ebs_type=1
      fi
    done
    if [ "$found_valid_ebs_type" -eq 0 ] ; then
      echo "ERROR: Invalid EBS volume type of $EBS_VOLUME_TYPE was specified."
      exit 9
    fi
    NEW_VOLUME_ID=$(aws --region $REGION ec2 create-volume --size $ENCRYPTED_EBS_VOLUME_SIZE --availability-zone $AVAILABILITY_ZONE --encrypted --volume-type $EBS_VOLUME_TYPE | grep "VolumeId" | awk -F"\"" '{print $4}')

    ## wait for the new volume to be available, then attach it
    while [ ! $(aws --region $REGION ec2 describe-volumes --volume-ids $NEW_VOLUME_ID --query Volumes[0].State | perl -i -pe 's{"}{}g') = available ]; do sleep 1; done
    aws --region $REGION ec2 attach-volume --volume-id $NEW_VOLUME_ID --instance-id i-$INSTANCE_ID --device /dev/xvdf

    ## if the attach fails, exit gracefully and continue
    if [ $? -ne 0 ]; then
    echo "attach failed... deleting volume"
    aws --region $REGION ec2 delete-volume --volume-id $NEW_VOLUME_ID
    exit 0
    fi
    ## lets copy the tags from the root volume to this volume
    aws --region $REGION ec2 create-tags --resources $NEW_VOLUME_ID --tags "file://$tmp_tag_file"
    
    ## 
    ## !!! WARNING !!!
    ## You may or may not want this delete-on-termination behavior for your situation
    ##
    aws --region $REGION ec2 modify-instance-attribute --instance-id $INSTANCE_ID --block-device-mappings "[{\"DeviceName\": \"/dev/xvdf\",\"Ebs\":{\"DeleteOnTermination\":true}}]"

    ## wait for the volume to actually be mounted and visible to the OS
    while [ ! -e /dev/xvdf ]; do sleep 1; done

    ## give the volume an FS if it doesnt have one
    if ! echo "$(blkid)" | grep -q "/dev/xvdf"; then
        mkfs.ext4 "/dev/xvdf"
    fi

    ## lets mount the ebs volume now
    mkdir -p /media/ebs-encrypted
    if ! grep -q "/dev/xvdf" "/etc/fstab"; then
        echo "/dev/xvdf     /media/ebs-encrypted      auto    defaults,nofail,comment=encryptedebs     0     2" >> /etc/fstab
        mount "/media/ebs-encrypted"
    fi
    
    ## clear out our temp file
    rm -f "$tmp_tag_file"
fi