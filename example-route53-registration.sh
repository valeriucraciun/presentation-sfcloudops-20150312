#!/bin/bash

HOSTNAME=mycoolhostname
BASE_DOMAIN=aws.mycompany.io

FQDN="${HOSTNAME}.${BASE_DOMAIN}"
LOCAL_IPV4=$(curl -sL 169.254.169.254/latest/meta-data/local-ipv4)

# we need to change the hostname and continue the entire rest of this script in a subshell so that the hostname change is effective
# Cram the hostname in a variety of places
echo $FQDN > /etc/hostname
echo $LOCAL_IPV4 $FQDN > /etc/hosts
echo 127.0.0.1 localhost >> /etc/hosts
perl -i -pe "s#HOSTNAME=.*#HOSTNAME=$FQDN#g" /etc/sysconfig/network
echo "$FQDN" > /proc/sys/kernel/hostname

# Make sure cloud init doesnt replace our hostname
perl -i -pe 's#preserve_hostname.*#preserve_hostname: true#g' /etc/cloud/cloud.cfg

# This call will use AWS instance profile creds
HOSTED_ZONE_ID=$(/usr/local/bin/aws route53 list-hosted-zones | grep -B1 "\"${BASE_DOMAIN}.\"" | grep hostedzone | awk -F\" '{print $4}' | awk -F\/ '{print $3}')

cat <<EOF >> /var/tmp/route53.json
{
    "Comment": "auto deploy entry",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "{RECORD}",
                "Type": "A",
                "TTL": 300,
                "ResourceRecords": [{ "Value": "{IP_ADDRESS}" }]
            }
        }
    ]
}
EOF

echo "Updating Route53..."
/usr/local/bin/aws route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch "$(cat /var/tmp/route53.json | perl -pe "s#{RECORD}#${FQDN}#g; s#{IP_ADDRESS}#${LOCAL_IPV4}#g")"