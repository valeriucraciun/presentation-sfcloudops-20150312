#!/bin/bash

YUM_REPO_BUCKET="my-aws-s3-yumrepo-bucketname"

wget -O /usr/lib/yum-plugins/s3iam.py https://github.com/seporaitis/yum-s3-iam/blob/master/s3iam.py
chown root: /usr/lib/yum-plugins/s3iam.py
chmod 0755 /usr/lib/yum-plugins/s3iam.py

wget -O /etc/yum/pluginconf.d/s3iam.conf https://github.com/seporaitis/yum-s3-iam/blob/master/s3iam.conf
chown root: /etc/yum/pluginconf.d/s3iam.conf
chmod 0755 /etc/yum/pluginconf.d/s3iam.conf

# Add our S3-based Yum repo
cat > /etc/yum.repos.d/${YUM_REPO_BUCKET}.repo <<EOF
[${YUM_REPO_BUCKET}]
name=${YUM_REPO_BUCKET}",
baseurl=https://${YUM_REPO_BUCKET}.s3.amazonaws.com/repo
failovermethod=priority
enabled=1
s3_enabled=1
gpgcheck=0
EOF

yum clean all
yum makecache