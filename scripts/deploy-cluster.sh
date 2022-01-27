export AI_URL='http://192.167.124.1:8090'
export CLUSTER_SSHKEY=$(cat ~/.ssh/id_ed25519.pub)
export PULL_SECRET=$(cat pull-secret.txt | jq -R .)

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
  "ssh_public_key": "${CLUSTER_SSHKEY}",
  "pull_secret": ${PULL_SECRET}
}
EOF
curl -s -X POST "$AI_URL/api/assisted-install/v2/clusters" \
  -d @./deployment-multinodes.json \
  --header "Content-Type: application/json" \
  | jq .


CLUSTER_ID=$(curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true" -H "accept: application/json" -H "get_unregistered_clusters: false"| jq -r '.[].id')

echo $CLUSTER_ID

echo  Build ISO


cat << EOF > ./discovery-iso-params.json
{
   "name": "ocpd_infra-env",
   "openshift_version": "4.9",
   "cluster_id": $CLUSTERID,
   "ssh_public_key": "$CLUSTER_SSHKEY",
   "pull_secret": $PULL_SECRET,
   "image_type": "full-iso"
}
EOF
curl -H "Content-Type: application/json" -X POST -d @discovery-iso-params.json \
 ${AI_URL}/api/assisted-install/v2/infra-envs | jq .

export INFRAENV_ID=$(curl -X GET "$AI_URL/api/assisted-install/v2/infra-envs" -H "accept: application/json" | jq -r '.[].id' | awk 'NR<2')
echo $INFRAENV_ID


ISO_URL=$(curl -X GET "$AI_URL/api/assisted-install/v2/infra-envs/$INFRAENV_ID/downloads/image-url" -H "accept: application/json"|jq -r .url)


echo download ISO

curl -X GET "$ISO_URL" -H "accept: application/octet-stream" -o -o /var/lib/libvirt/images/discovery_image_ocpd.iso



echo Create and start Masters

terraform -chdir=/opt/terraform/ocp4-ai-cluster init
terraform -chdir=/opt/terraform/ocp4-ai-cluster/ apply -auto-approve



echo  Done!!!

echo Wait for discovery process to happen

Sleep 180 

echo Assign Master role to discovered nodes

for i in `curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true"\
     -H "accept: application/json" -H "get_unregistered_clusters: false"| jq -r '.[].hosts[].id'| awk 'NR>0' |awk '{print $1;}'`
do curl -X PATCH "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID" -H "accept: application/json" -H "Content-Type: application/json" -d "{ \"hosts_roles\": [ { \"id\": \"$i\", \"role\": \"master\" } ]}"
done


echo set api IP

curl -X PATCH "$AI_URL/api/assisted-install/v2/clusters/$CLUSTER_ID" -H "accept: application/json" -H "Content-Type: application/json" -d "{ \"api_vip\": \"192.167.124.7\"}"

echo Start workers
for i in {1..3}
do virsh start ocp4-worker$i
done

sleep 180

echo Start instalation

curl -X POST \
  "$AI_URL/api/assisted-install/v2/clusters/$CLUSTER_ID/actions/install" \
  -H "accept: application/json" \
  -H "Content-Type: application/json"

STATUS=$(curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true" -H "accept: application/json" -H "get_unregistered_clusters: false"| jq -r '.[].progress.total_percentage')

echo Wait for install to complete

while [[ $STATUS != 100 ]]
do
sleep 5
STATUS=$(curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true" -H "accept: application/json" -H "get_unregistered_clusters: false"| jq -r '.[].progress.total_percentage')
done

echo 
mkdir ~/.kube
curl -X GET '$AI_URL/api/assisted-install/v2/clusters/$CLUSTER_ID/downloads/credentials?file_name=kubeconfig' \
     -H 'accept: application/octet-stream' > /root/.kube/config

