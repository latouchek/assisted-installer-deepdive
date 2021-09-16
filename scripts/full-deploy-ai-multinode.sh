AI_URL='http://192.167.124.1:8090'

curl -s -X POST "$AI_URL/api/assisted-install/v1/clusters" \
  -d @./deployment-multinodes.json \
  --header "Content-Type: application/json" \
  | jq .


CLUSTER_ID=$(curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true" -H "accept: application/json" -H "get_unregistered_clusters: false"| jq -r '.[].id')

echo $CLUSTER_ID

#command to POST a request for Assisted-Service to build the deployment ISO:
curl -s -X POST "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID/downloads/image" \
  -d @iso-params.json \
  --header "Content-Type: application/json" \
  | jq '.'

#download ISO
curl -L "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID/downloads/image" -o /var/lib/libvirt/images/default/discovery_image_ocpd.iso
####start masters##


####wait for discovery process to happen#####

###get cluster info
curl -s -X GET   --header "Content-Type: application/json"   "$AI_URL/api/assisted-install/v1/clusters"   | jq .

####assign Master role to discovered nodes####

for i in `curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true"\
     -H "accept: application/json" -H "get_unregistered_clusters: false"| jq -r '.[].hosts[].id'| awk 'NR>0' |awk '{print $1;}'`
do curl -X PATCH "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID" -H "accept: application/json" -H "Content-Type: application/json" -d "{ \"hosts_roles\": [ { \"id\": \"$i\", \"role\": \"master\" } ]}"
done


###set api IP###

curl -X PATCH "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID" -H "accept: application/json" -H "Content-Type: application/json" -d "{ \"api_vip\": \"192.167.124.7\"}"


####Start instalation
curl -X POST \
  "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID/actions/install" \
  -H "accept: application/json" \
  -H "Content-Type: application/json"
