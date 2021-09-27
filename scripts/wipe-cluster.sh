CLUSTER_ID=$(curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true" -H "accept: application/json" -H "get_unregistered_clusters: false"| jq -r '.[].id')

echo Wiping cluster: $CLUSTER_ID

curl -X DELETE "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID" -H "accept: application/json"

echo Wiping nodes

terraform -chdir=/opt/terraform-ocp4-cluster-ai destroy -auto-approve

rm -rf ~/.kube