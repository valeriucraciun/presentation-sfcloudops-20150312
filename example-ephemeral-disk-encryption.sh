#!/bin/bash

CRYPT_PASSWORD="my-super-secret-thing-that-nobody-should-EVER-know-or-remember"

curl -sL 169.254.169.254/latest/meta-data/block-device-mapping/ | grep ephemeral | while read disk_map; do
    local_map=$(curl -sL "169.254.169.254/latest/meta-data/block-device-mapping/$disk_map" | tail -c 2)
    ## encrypt the ephemeral storage now, before cloud-init runs
    df -h | grep "/media/" | egrep "/dev/[a-z]+$local_map" | while read disk size used avail use_percent mount_on; do
        umount --force "${mount_on}"
        cryptsetup luksFormat "${disk}" <<EOF
${CRYPT_PASSWORD}
EOF
        devMapping="cryptdev${disk##${disk%%?}}"
        cryptsetup luksOpen "${disk}" "${devMapping}"<<EOF
${CRYPT_PASSWORD}
EOF
        mkfs.ext4 -m 0 "/dev/mapper/${devMapping}"
        mkdir -p "${mount_on}"
        mount "/dev/mapper/${devMapping}" "${mount_on}"
        chown -R ec2-user: "${mount_on}"
    done
done
