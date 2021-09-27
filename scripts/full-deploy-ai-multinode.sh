export AI_URL='http://192.167.124.1:8090'
export CLUSTER_SSHKEY=$(cat ~/.ssh/id_ed25519.pub)
export PULL_SECRET=$(cat pull-secret.txt | jq -R .)

curl -s -X POST "$AI_URL/api/assisted-install/v1/clusters" \
  -d @./deployment-multinodes.json \
  --header "Content-Type: application/json" \
  | jq .


CLUSTER_ID=$(curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true" -H "accept: application/json" -H "get_unregistered_clusters: false"| jq -r '.[].id')

echo $CLUSTER_ID

echo  Build ISO

curl -s -X POST "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID/downloads/image" \
  -d @iso-params.json \
  --header "Content-Type: application/json" \
  | jq '.'

echo download ISO

curl -L "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID/downloads/image" -o /var/lib/libvirt/images/default/discovery_image_ocpd.iso



echo Create and start Masters

terraform -chdir=/opt/terraform-ocp4-cluster-ai init
terraform -chdir=/opt/terraform-ocp4-cluster-ai/ apply -auto-approve



echo  Done!!!

echo Wait for discovery process to happen

Sleep 180 

echo Assign Master role to discovered nodes

for i in `curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true"\
     -H "accept: application/json" -H "get_unregistered_clusters: false"| jq -r '.[].hosts[].id'| awk 'NR>0' |awk '{print $1;}'`
do curl -X PATCH "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID" -H "accept: application/json" -H "Content-Type: application/json" -d "{ \"hosts_roles\": [ { \"id\": \"$i\", \"role\": \"master\" } ]}"
done


echo set api IP

curl -X PATCH "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID" -H "accept: application/json" -H "Content-Type: application/json" -d "{ \"api_vip\": \"192.167.124.7\"}"

echo Start workers
for i in {1..2}
do virsh start ocp4-worker$i
done

sleep 180

echo Start instalation

curl -X POST \
  "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID/actions/install" \
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
curl -X GET "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID/downloads/kubeconfig" -H "accept: application/octet-stream" > .kube/config


