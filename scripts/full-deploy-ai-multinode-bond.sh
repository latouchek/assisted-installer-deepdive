export AI_URL='http://192.167.124.1:8090'
export CLUSTER_SSHKEY=$(cat ~/.ssh/id_ed25519.pub)
export PULL_SECRET=$(cat pull-secret.txt | jq -R .)

#####Create Cluster definition data file ######

cat << EOF > ./deployment-multinodes.json
{
  "kind": "Cluster",
  "name": "ocpd",
  "openshift_version": "4.9",
  "base_dns_domain": "lab.local",
  "hyperthreading": "all",
  "ingress_vip": "192.167.124.8",
  "schedulable_masters": false,
  "platform": {
    "type": "baremetal"
   },
  "user_managed_networking": false,
  "cluster_networks": [
    {
      "cidr": "10.128.0.0/14",
      "host_prefix": 23
    }
  ],
  "service_networks": [
    {
      "cidr": "172.31.0.0/16"
    }
  ],
  "machine_networks": [
    {
      "cidr": "192.167.124.0/24"
    }
  ],
  "network_type": "OVNKubernetes",
  "additional_ntp_source": "ntp1.hetzner.de",
  "vip_dhcp_allocation": false,
  "high_availability_mode": "Full",
  "hosts": [],
  "ssh_public_key": "$CLUSTER_SSHKEY",
  "pull_secret": "$PULL_SECRET"
}
EOF 


#####Create cluster definition

curl -s -X POST "$AI_URL/api/assisted-install/v1/clusters" \
  -d @./deployment-multinodes.json \
  --header "Content-Type: application/json" \
  | jq .


CLUSTER_ID=$(curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true" -H "accept: application/json" -H "get_unregistered_clusters: false"| jq -r '.[].id')

echo $CLUSTER_ID



#########create definition file for bond####
jq -n  --arg NMSTATE_YAML1 "$(cat nmstate-bond-worker0.yaml)" --arg NMSTATE_YAML2 "$(cat nmstate-bond-worker1.yaml)" '{
  "ssh_public_key": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM4Hm8ZgmBIduPkPjNMijB6KMCYENnJD7W9piKzjxZxa root@esxi-hetzner.lab.local",
  "image_type": "full-iso",
  "static_network_config": [
    {
      "network_yaml": $NMSTATE_YAML1,
      "mac_interface_map": [{"mac_address": "aa:bb:cc:11:42:20", "logical_nic_name": "ens3"}, {"mac_address": "aa:bb:cc:11:42:50", "logical_nic_name": "ens4"},{"mac_address": "aa:bb:cc:11:42:60", "logical_nic_name": "ens5"}]
    },
    {
      "network_yaml": $NMSTATE_YAML2,
      "mac_interface_map": [{"mac_address": "aa:bb:cc:11:42:21", "logical_nic_name": "ens3"}, {"mac_address": "aa:bb:cc:11:42:51", "logical_nic_name": "ens4"},{"mac_address": "aa:bb:cc:11:42:61", "logical_nic_name": "ens5"}]
     }
  ]
}' > data-net


#####Create image####
curl -H "Content-Type: application/json" -X POST -d @data-net ${AI_URL}/api/assisted-install/v1/clusters/$CLUSTER_ID/downloads/image | jq .


#####Download image#####

curl -L "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID/downloads/image" -o /var/lib/libvirt/images/discovery_image_ocpd.iso

####start masters##

terraform  -chdir=/opt/terraform/ai-bond apply -auto-approve



####

for i in `curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true"\
     -H "accept: application/json" -H "get_unregistered_clusters: false"| jq -r '.[].hosts[].id'| awk 'NR>0' |awk '{print $1;}'`
do curl -X PATCH "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID" -H "accept: application/json" -H "Content-Type: application/json" -d "{ \"hosts_roles\": [ { \"id\": \"$i\", \"role\": \"master\" } ]}"
done


###set api IP###

curl -X PATCH "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID" -H "accept: application/json" -H "Content-Type: application/json" -d "{ \"api_vip\": \"192.167.124.7\"}"

###Start workers####
for i in {0..1}
do virsh start ocp4-worker$i
done

sleep 180

curl -X POST \
  "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID/actions/install" \
  -H "accept: application/json" \
  -H "Content-Type: application/json"

echo Wait for install to complete

while [[ $STATUS != 100 ]]
do
sleep 5
STATUS=$(curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true" -H "accept: application/json" -H "get_unregistered_clusters: false"| jq -r '.[].progress.total_percentage')
done

echo 
mkdir ~/.kube
curl -X GET "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID/downloads/kubeconfig" -H "accept: application/octet-stream" > .kube/config
