export AI_URL='http://192.167.124.1:8090'
export CLUSTER_SSHKEY=$(cat ~/.ssh/id_ed25519.pub)
export PULL_SECRET=$(cat pull-secret.txt | jq -R .)

curl -s -X POST "$AI_URL/api/assisted-install/v1/clusters" \
  -d @./deployment-multinodes-calico.json \
  --header "Content-Type: application/json" \
  | jq .


CLUSTER_ID=$(curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true" -H "accept: application/json" -H "get_unregistered_clusters: false"| jq -r '.[].id')

echo $CLUSTER_ID

####patch cluster and set networking to Calico###


curl \
  --header "Content-Type: application/json" \
  --request PATCH \
  --data '"{\"networking\":{\"networkType\":\"Calico\"}}"' \
  "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID/install-config"

curl -s -X GET \
  --header "Content-Type: application/json" \
  "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID/install-config" | jq -r .

#Build the deployment ISO:
curl -s -X POST "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID/downloads/image" \
  -d @iso-params.json \
  --header "Content-Type: application/json" \
  | jq '.'

#Download ISO
curl -L "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID/downloads/image" -o /var/lib/libvirt/images/default/discovery_image_ocpd.iso

####start masters##
terraform -chdir=/opt/terraform-ocp4-cluster-ai init
terraform -chdir=/opt/terraform-ocp4-cluster-ai/ apply -auto-approve


echo  Done!!!

echo Download Calico manifests

mkdir manifests
curl https://docs.projectcalico.org/manifests/ocp/crds/01-crd-apiserver.yaml -o manifests/01-crd-apiserver.yaml
curl https://docs.projectcalico.org/manifests/ocp/crds/01-crd-installation.yaml -o manifests/01-crd-installation.yaml
curl https://docs.projectcalico.org/manifests/ocp/crds/01-crd-imageset.yaml -o manifests/01-crd-imageset.yaml
curl https://docs.projectcalico.org/manifests/ocp/crds/01-crd-tigerastatus.yaml -o manifests/01-crd-tigerastatus.yaml
curl https://docs.projectcalico.org/manifests/ocp/crds/calico/kdd/crd.projectcalico.org_bgpconfigurations.yaml -o manifests/crd.projectcalico.org_bgpconfigurations.yaml
curl https://docs.projectcalico.org/manifests/ocp/crds/calico/kdd/crd.projectcalico.org_bgppeers.yaml -o manifests/crd.projectcalico.org_bgppeers.yaml
curl https://docs.projectcalico.org/manifests/ocp/crds/calico/kdd/crd.projectcalico.org_blockaffinities.yaml -o manifests/crd.projectcalico.org_blockaffinities.yaml
curl https://docs.projectcalico.org/manifests/ocp/crds/calico/kdd/crd.projectcalico.org_clusterinformations.yaml -o manifests/crd.projectcalico.org_clusterinformations.yaml
curl https://docs.projectcalico.org/manifests/ocp/crds/calico/kdd/crd.projectcalico.org_felixconfigurations.yaml -o manifests/crd.projectcalico.org_felixconfigurations.yaml
curl https://docs.projectcalico.org/manifests/ocp/crds/calico/kdd/crd.projectcalico.org_globalnetworkpolicies.yaml -o manifests/crd.projectcalico.org_globalnetworkpolicies.yaml
curl https://docs.projectcalico.org/manifests/ocp/crds/calico/kdd/crd.projectcalico.org_globalnetworksets.yaml -o manifests/crd.projectcalico.org_globalnetworksets.yaml
curl https://docs.projectcalico.org/manifests/ocp/crds/calico/kdd/crd.projectcalico.org_hostendpoints.yaml -o manifests/crd.projectcalico.org_hostendpoints.yaml
curl https://docs.projectcalico.org/manifests/ocp/crds/calico/kdd/crd.projectcalico.org_ipamblocks.yaml -o manifests/crd.projectcalico.org_ipamblocks.yaml
curl https://docs.projectcalico.org/manifests/ocp/crds/calico/kdd/crd.projectcalico.org_ipamconfigs.yaml -o manifests/crd.projectcalico.org_ipamconfigs.yaml
curl https://docs.projectcalico.org/manifests/ocp/crds/calico/kdd/crd.projectcalico.org_ipamhandles.yaml -o manifests/crd.projectcalico.org_ipamhandles.yaml
curl https://docs.projectcalico.org/manifests/ocp/crds/calico/kdd/crd.projectcalico.org_ippools.yaml -o manifests/crd.projectcalico.org_ippools.yaml
curl https://docs.projectcalico.org/manifests/ocp/crds/calico/kdd/crd.projectcalico.org_kubecontrollersconfigurations.yaml -o manifests/crd.projectcalico.org_kubecontrollersconfigurations.yaml
curl https://docs.projectcalico.org/manifests/ocp/crds/calico/kdd/crd.projectcalico.org_networkpolicies.yaml -o manifests/crd.projectcalico.org_networkpolicies.yaml
curl https://docs.projectcalico.org/manifests/ocp/crds/calico/kdd/crd.projectcalico.org_networksets.yaml -o manifests/crd.projectcalico.org_networksets.yaml
curl https://docs.projectcalico.org/manifests/ocp/tigera-operator/00-namespace-tigera-operator.yaml -o manifests/00-namespace-tigera-operator.yaml
curl https://docs.projectcalico.org/manifests/ocp/tigera-operator/02-rolebinding-tigera-operator.yaml -o manifests/02-rolebinding-tigera-operator.yaml
curl https://docs.projectcalico.org/manifests/ocp/tigera-operator/02-role-tigera-operator.yaml -o manifests/02-role-tigera-operator.yaml
curl https://docs.projectcalico.org/manifests/ocp/tigera-operator/02-serviceaccount-tigera-operator.yaml -o manifests/02-serviceaccount-tigera-operator.yaml
curl https://docs.projectcalico.org/manifests/ocp/tigera-operator/02-configmap-calico-resources.yaml -o manifests/02-configmap-calico-resources.yaml
curl https://docs.projectcalico.org/manifests/ocp/tigera-operator/02-tigera-operator.yaml -o manifests/02-tigera-operator.yaml
curl https://docs.projectcalico.org/manifests/ocp/01-cr-installation.yaml -o manifests/01-cr-installation.yaml
curl https://docs.projectcalico.org/manifests/ocp/01-cr-apiserver.yaml -o manifests/01-cr-apiserver.yaml

for i in `ls manifests`
do
 j=$(cat manifests/$i | base64 -w 0)
 curl -X POST "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID/manifests" \
 -H "accept: application/json" -H "Content-Type: application/json" \
 -d "{ \"folder\": \"manifests\", \"file_name\": \"$i\", \"content\": \"$j\"}"
done

#####Realtime kernel for workers####
echo Create a machine config for the real-time kernel


cat << EOF > 99-worker-realtime.yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: "worker"
  name: 99-worker-realtime
spec:
  kernelType: realtime
EOF

j=$(cat 99-worker-realtime.yaml | base64 -w 0)
i=99-worker-realtime.yaml
curl -X POST "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID/manifests" -H "accept: application/json" -H "Content-Type: application/json" -d "{ \"folder\": \"openshift\", \"file_name\": \"$i\", \"content\": \"$j\"}"

echo Wait for the discovery process to happen

sleep 180  ####adjust to ur infra
echo Get cluster info
curl -s -X GET   --header "Content-Type: application/json"   "$AI_URL/api/assisted-install/v1/clusters"   | jq .

echo Assign Master role to discovered nodes

for i in `curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true"\
     -H "accept: application/json" -H "get_unregistered_clusters: false"| jq -r '.[].hosts[].id'| awk 'NR>0' |awk '{print $1;}'`
do curl -X PATCH "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID" -H "accept: application/json" -H "Content-Type: application/json" -d "{ \"hosts_roles\": [ { \"id\": \"$i\", \"role\": \"master\" } ]}"
done


echo Set API IP

curl -X PATCH "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID" -H "accept: application/json" -H "Content-Type: application/json" -d "{ \"api_vip\": \"192.167.124.7\"}"

echo Start workers

for i in {1..2}
do virsh start ocp4-worker$i
done

sleep 180 ####adjust to ur infra


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


