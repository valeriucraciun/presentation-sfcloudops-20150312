#!/bin/bash

cat > /etc/chef/runlist.json <<EOF
{
	"name": "$(hostname)",
    "company": "",
    "tags": [],
    "chef_environment": "_default",
    "mycookbook": {
    	"myattrib1": "val1",
    	"myattrib2": "val2"
    },
    "run_list": ["recipe[mycookbook::default]"]
}
EOF

# Install local copy of chef repo
# This RPM should put your chef repo at /opt/chef-repo in order to work with the values below
yum -y install your-local-chef-repo.rpm

# Probably want to copy this somewhere convenient/local/fast
sudo yum localinstall https://opscode-omnibus-packages.s3.amazonaws.com/el/6/x86_64/chef-12.1.0-1.el6.x86_64.rpm

# Bootstrap chef and initiate the first chef-client run
mkdir -p /etc/chef

cat <<EOF > /etc/chef/encrypted_data_bag_secret
$ENCRYPTED_DATA_BAG_SECRET
EOF

cat <<EOF > /etc/chef/solo.rb
log_level              :info
log_location           "/var/log/chef-client.log"
node_name              "$(hostname)"
json_attribs           "/etc/chef/runlist.json"
data_bag_path          "/opt/chef-repo/data_bags"
cookbook_path          "/opt/chef-repo/cookbooks"
environment_path       "/opt/chef-repo/environments"
EOF

# Lots of inexplicable spurious errors during initial chef run (sometimes jdk or random yum 
# packages fail to install). So first few chef runs are not daemonized.
for i in {1..3}; do
    chef-solo >> /var/log/chef-client.log 2>&1 || echo "Chef run failed..."
    yum clean all
    sleep 10
done

# Add the chef-client to the crontab in case it dies
if ! echo "$(crontab -l)" | grep -q "chef-solo"; then
    echo "*/15 * * * * nohup chef-solo 2>&1 >> /var/log/chef-client.log" | crontab
fi