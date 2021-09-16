




# Assisted Installer on premise deep dive




## Introduction

In this series of blog posts ,we will demonstrate how Infra as a code becomes a reality with OpenShift Assisted Installer onprem and how we can leverage on its powerful API to automate and tweak OCP4 deployment on baremetal or Vsphere.


## Lab Preparation

In this lab we will simulate Baremetal nodes with KVM VMs. Terraform will be use to orchestrate this virtual infrastructure.
A minimum of 256Go of Ram and 500G SSD drive is recommended.
In order to have everything set and all the bits installed, run the following commands:
```bash
git clone https://github.com/latouchek/assisted-installer-deepdive.git
cd assisted-installer-deepdive
cp -r terraform /opt/
cd scripts
sh prepare-kvm-host
 ```

The script creates a dedicated ocp network. It is mandatory to have a DNS and a static DHCP server on that network .
A dnsmasq.conf template is provided in assisted-installer-deepdive/conf/ with mac adresses matching the OCP VMs that we will deploy later. It can either be run on the host or on a dedicated VM/container
## Part I : Deploying the OpenShift Assisted Installer service on premise

####  1. Get the bits and build the service!

```bash
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
setenforce 0
dnf install -y @container-tools
dnf group install "Development Tools" -y
dnf -y install python3-pip socat make tmux git jq crun
git clone https://github.com/openshift/assisted-service
cd assisted-service
IP=192.167.124.1
AI_URL=http://$IP:8090
```
Modify **onprem-environment** and **Makefile** to set proper URL and port forwarding

```bash
sed -i "s@SERVICE_BASE_URL=.*@SERVICE_BASE_URL=$AI_URL@" onprem-environment
sed -i "s/5432,8000,8090,8080/5432:5432 -p 8000:8000 -p 8090:8090 -p 8080:8080/" Makefile
make deploy-onprem
.
.
.
```
If everything went well, we should see 4 containers running inside a pod
```bash
[root@kvm-host ~]# podman ps
CONTAINER ID  IMAGE                                          COMMAND               CREATED             STATUS                 PORTS                                                                                           NAMES
a940818185cb  k8s.gcr.io/pause:3.5                                                 3 minutes ago       Up 2 minutes ago       0.0.0.0:5432->5432/tcp, 0.0.0.0:8000->8000/tcp, 0.0.0.0:8080->8080/tcp, 0.0.0.0:8090->8090/tcp  59b56cb07140-infra
d94a46c8b515  quay.io/ocpmetal/postgresql-12-centos7:latest  run-postgresql        2 minutes ago       Up 2 minutes ago       0.0.0.0:5432->5432/tcp, 0.0.0.0:8000->8000/tcp, 0.0.0.0:8080->8080/tcp, 0.0.0.0:8090->8090/tcp  db
8c0e90d8c4fa  quay.io/ocpmetal/ocp-metal-ui:latest           /opt/bitnami/scri...  About a minute ago  Up About a minute ago  0.0.0.0:5432->5432/tcp, 0.0.0.0:8000->8000/tcp, 0.0.0.0:8080->8080/tcp, 0.0.0.0:8090->8090/tcp  ui
e98627cdc5f8  quay.io/ocpmetal/assisted-service:latest       /assisted-service     42 seconds ago      Up 43 seconds ago      0.0.0.0:5432->5432/tcp, 0.0.0.0:8000->8000/tcp, 0.0.0.0:8080->8080/tcp, 0.0.0.0:8090->8090/tcp  installer

```

```bash
[root@kvm-host ~] podman pod ps
POD ID        NAME                STATUS      CREATED        INFRA ID      # OF CONTAINERS
59b56cb07140  assisted-installer  Running     4 minutes ago  a940818185cb  4

```
API should be accessible at  http://192.167.124.1:8090 and GUI at http://192.167.124.1:8080/

API documentation can be found [here](https://generator.swagger.io/?url=https://raw.githubusercontent.com/openshift/assisted-service/master/swagger.yaml)
#### 2.  How does it work ?
In order to provision a cluster the following process must be followed
 - Create a new OpenShift cluster definition in a json file
  - Register the new cluster by presenting the definition data to the API
  - Create a discovery boot media the nodes will boot from in order to be introspected and validated
  - Assign roles to introspected nodes and complete the cluster definition
  - Trigger the deployment

## Part II : Using the Assisted Installer API
In this part we will show how to deploy a 5 nodes OCP cluster y following the steps we mentioned above.
Even though this lab is purely cli based it is recommended to have the [UI](http://192.167.124.1:8080/) on sight to understand the whole process.
#### 1. Deploy  our first cluster with AI  API

 - Create a cluster definition file
    ```bash
    export CLUSTER_SSHKEY=$(cat ~/.ssh/id_ed25519.pub)
    export PULL_SECRET=$(cat pull-secret.txt | jq -R .)
    cat << EOF > ./deployment-multinodes.json
    {
      "kind": "Cluster",
      "name": "ocpd",  
      "openshift_version": "4.8",
      "ocp_release_image": "quay.io/openshift-release-dev/ocp-release:4.8.5-x86_64",
      "base_dns_domain": "lab.local",
      "hyperthreading": "all",
      "ingress_vip": "192.167.124.8",
      "schedulable_masters": false,
      "high_availability_mode": "Full",
      "user_managed_networking": false,
      "platform": {
        "type": "baremetal"
       },
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
      "ssh_public_key": "$CLUSTER_SSHKEY",
      "pull_secret": $PULL_SECRET
    }
    EOF
   ```

   **high_availability_mode** and **schedulable_masters** parameters let you decide what type of cluster    you want to install. Here is how to set those parameters:

   - 3 nodes clusters:  **"high_availability_mode": "Full"** and **"schedulable_masters": true**
   - 3+ nodes clusters:   **"high_availability_mode": "Full"** and **"schedulable_masters": false**
   - Single Node:   **"high_availability_mode": "None"**

   You can choose if you want to handle  **loadbalancing** in house or leave it to OCP by  setting **user_managed_networking** to **true** or **false**. In both case, DHCP and DNS server are mandatory (Only DNS in the case of a static IP deployment)


 - Use  deployment-multinodes.json to register the new cluster

   ```bash
   AI_URL='http://192.167.124.1:8090'
   curl -s -X POST "$AI_URL/api/assisted-install/v1/clusters" \
      -d @./deployment-multinodes.json --header "Content-Type: application/json" | jq .
   ```

 - Check cluster is registered
   Once the cluster definition has been sent to an the API we should be able to retrieve its unique id
   ```bash
    CLUSTER_ID=$(curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true" -H "accept: application/json" -H "get_unregistered_clusters: false"| jq -r '.[].id')
    [root@kvm-host ~] echo $CLUSTER_ID
    43b9c2f0-218e-4e76-8889-938fd52d6290
    ```
 - Check the new cluster status
    ```bash
    [root@kvm-host ~]# curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true" -H "accept: application/json" -H "get_unregistered_clusters: false"| jq -r '.[].status'

    pending-for-input
    ```


   When registering a cluster, the assisted installer runs a series of validation tests to assess if the cluster is ready to be  deployed.
  'pending-for-input' tells us we need to take some actions. Let's take a look at validations_info:
    ```bash
   curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true" -H "accept: application/json" -H "get_unregistered_clusters: false"| jq -r '.[].validations_info'|jq .
     ```
   We can see below that the installer is waiting for the hosts . Before building the hosts, we need to create the Discovery ISO.

    ```bash

    {
      "id": "sufficient-masters-count",
      "status": "failure",
      "message": "Clusters must have exactly 3 dedicated masters. Please either add hosts, or disable the worker host"
      }
        ],

    {
      "id": "cluster-cidr-defined",
      "status": "success",
      "message": "The Cluster Network CIDR is defined."
    },
    ```
- Build  the discovery boot ISO
The discovery boot ISO is a live CoreOS image that the nodes will boot from. Once booted an introspection will be performed by the discovery agent and datas sent to the assisted service. If the node passes the validation tests its **status_info** will be **"Host is ready to be installed"**.
We need some extra parameters to be injected into the ISO . To do so, we create a data file as described bellow:
    ```bash
    cat << EOF > ./discovery-iso-params.json
   {
    "ssh_public_key": "$CLUSTER_SSHKEY",
     "pull_secret": $PULL_SECRET,
     "image_type": "full-iso"
    }
   EOF
   ```
  ISO is now ready to be built! Let's make the API call! As you can see we use the data file so pull-secret and ssh public key are injected into the live ISO.
     ```bash
   curl -s -X POST "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID/downloads/image" \  
  -d @discovery-iso-params.json \
  --header "Content-Type: application/json" \
  | jq '.'
    ```
  In real world we would need to present this ISO to our hosts so they can boot it from. Because we are using KVM, we are going to download the ISO in the libvirt images directory and later create the VMs

  ```bash
  curl \
    -L "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID/downloads/image" \
    -o /var/lib/libvirt/images/default/discovery_image_ocpd.iso
  ```
- Start the nodes and the discovery process
   In this lab, BM nodes are virtual and need to be provisioned first. A Terraform file is provided and will build 3 Masters, 4 workers. All the VMS are using the previously generated ISO to boot. Run the following commands inside the Terraform folder

  ```bash
  [root@kvm-host terraform-ocp4-cluster-ai] terraform init ; terraform apply -auto-approve



   Apply complete! Resources: 24 added, 0 changed, 0 destroyed.
    ```



     ```bash

  [root@kvm-host terraform-ocp4-cluster-ai] virsh list --all
   Id   Name               State
  -----------------------------------
   59   ocp4-master3       running
   60   ocp4-master1       running
   61   ocp4-master2       running
   -    ocp4-worker1       shut off
   -    ocp4-worker1-ht    shut off
   -    ocp4-worker2       shut off
   -    ocp4-worker3       shut off
  ```
  Only the master nodes will start for now. Wait 1 mn for them to be discovered  and check validations_info


  ```bash
   curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true" \
   -H "accept: application/json" \
   -H "get_unregistered_clusters: false"| jq -r '.[].progress'
   ```
   ```bash
     ........
     "hosts-data": [
       {
         "id": "all-hosts-are-ready-to-install",
         "status": "success",
         "message": "All hosts in the cluster are ready to install."
       },
       {
         "id": "sufficient-masters-count",
         "status": "success",
         "message": "The cluster has a sufficient number of master candidates."
       }
       .........
    ```
  Our hosts have been validated and are ready to be installed. Let's take a closer look at the discovery data!
 - Retrieve the discovery hosts datas with an API call



   ```bash
   [root@kvm-host ~]# curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true" \
   -H "accept: application/json" \
   -H "get_unregistered_clusters: false"| jq -r '.[].hosts'
   ```

    ```bash
     .......
     {
    "checked_in_at": "2021-09-15T22:57:25.484Z",
    "cluster_id": "71db492e-207e-47eb-af7b-c7c716c7e09d",
    "connectivity": "{\"remote_hosts\":[{\"host_id\":\"2121a000-d27e-4596-a408-6813d3114caf\",\"l2_connectivity\":[{\"outgoing_ip_address\":\"192.167.124.12\",\"outgoing_nic\":\"ens3\",\"remote_ip_address\":\"192.167.124.13\",\"remote_mac\":\"aa:bb:cc:11:42:11\",\"successful\":true}],\"l3_connectivity\":[{\"average_rtt_ms\":0.304,\"outgoing_nic\":\"ens3\",\"remote_ip_address\":\"192.167.124.13\",\"successful\":true}]},{\"host_id\":\"84083091-8c0c-470b-a157-d002dbeed785\",\"l2_connectivity\":[{\"outgoing_ip_address\":\"192.167.124.12\",\"outgoing_nic\":\"ens3\",\"remote_ip_address\":\"192.167.124.14\",\"remote_mac\":\"aa:bb:cc:11:42:12\",\"successful\":true}],\"l3_connectivity\":[{\"average_rtt_ms\":0.237,\"outgoing_nic\":\"ens3\",\"remote_ip_address\":\"192.167.124.14\",\"successful\":true}]}]}",
    "created_at": "2021-09-15T19:23:23.614Z",
    "discovery_agent_version": "latest",
    "domain_name_resolutions": "{\"resolutions\":[{\"domain_name\":\"api.ocpd.lab.local\",\"ipv4_addresses\":[\"192.167.124.7\"],\"ipv6_addresses\":[]},{\"domain_name\":\"api-int.ocpd.lab.local\",\"ipv4_addresses\":[],\"ipv6_addresses\":[]},{\"domain_name\":\"console-openshift-console.apps.ocpd.lab.local\",\"ipv4_addresses\":[\"192.167.124.8\"],\"ipv6_addresses\":[]},{\"domain_name\":\"validateNoWildcardDNS.ocpd.lab.local\",\"ipv4_addresses\":[],\"ipv6_addresses\":[]}]}",
    "href": "/api/assisted-install/v2/infra-envs/71db492e-207e-47eb-af7b-c7c716c7e09d/hosts/fa89d7cd-c2d9-4f26-bd78-155647a32b04",
    "id": "fa89d7cd-c2d9-4f26-bd78-155647a32b04",
    "infra_env_id": "71db492e-207e-47eb-af7b-c7c716c7e09d",
    "installation_disk_id": "/dev/disk/by-path/pci-0000:00:05.0",
    "installation_disk_path": "/dev/vda",
    "inventory": "{\"bmc_address\":\"0.0.0.0\",\"bmc_v6address\":\"::/0\",\"boot\":{\"current_boot_mode\":\"bios\"},\"cpu\":{\"architecture\":\"x86_64\",\"count\":12,\"flags\":[\"fpu\",\"vme\",\"de\",\"pse\",\"tsc\",\"msr\",\"pae\",\"mce\",\"cx8\",\"apic\",\"sep\",\"mtrr\",\"pge\",\"mca\",\"cmov\",\"pat\",\"pse36\",\"clflush\",\"mmx\",\"fxsr\",\"sse\",\"sse2\",\"ss\",\"syscall\",\"nx\",\"pdpe1gb\",\"rdtscp\",\"lm\",\"constant_tsc\",\"arch_perfmon\",\"rep_good\",\"nopl\",\"xtopology\",\"cpuid\",\"tsc_known_freq\",\"pni\",\"pclmulqdq\",\"vmx\",\"ssse3\",\"fma\",\"cx16\",\"pdcm\",\"pcid\",\"sse4_1\",\"sse4_2\",\"x2apic\",\"movbe\",\"popcnt\",\"tsc_deadline_timer\",\"aes\",\"xsave\",\"avx\",\"f16c\",\"rdrand\",\"hypervisor\",\"lahf_lm\",\"abm\",\"cpuid_fault\",\"invpcid_single\",\"pti\",\"ssbd\",\"ibrs\",\"ibpb\",\"stibp\",\"tpr_shadow\",\"vnmi\",\"flexpriority\",\"ept\",\"vpid\",\"ept_ad\",\"fsgsbase\",\"tsc_adjust\",\"bmi1\",\"avx2\",\"smep\",\"bmi2\",\"erms\",\"invpcid\",\"xsaveopt\",\"arat\",\"umip\",\"md_clear\",\"arch_capabilities\"],\"frequency\":3491.914,\"model_name\":\"Intel(R) Xeon(R) CPU E5-1650 v3 @ 3.50GHz\"},\"disks\":[{\"bootable\":true,\"by_path\":\"/dev/disk/by-path/pci-0000:00:01.1-ata-1\",\"drive_type\":\"ODD\",\"hctl\":\"0:0:0:0\",\"id\":\"/dev/disk/by-path/pci-0000:00:01.1-ata-1\",\"installation_eligibility\":{\"not_eligible_reasons\":[\"Disk is removable\",\"Disk is too small (disk only has 1.0 GB, but 120 GB are required)\",\"Drive type is ODD, it must be one of HDD, SSD.\"]},\"is_installation_media\":true,\"model\":\"QEMU_DVD-ROM\",\"name\":\"sr0\",\"path\":\"/dev/sr0\",\"removable\":true,\"serial\":\"QM00001\",\"size_bytes\":1031798784,\"smart\":\"{\\\"json_format_version\\\":[1,0],\\\"smartctl\\\":{\\\"version\\\":[7,1],\\\"svn_revision\\\":\\\"5022\\\",\\\"platform_info\\\":\\\"x86_64-linux-4.18.0-305.10.2.el8_4.x86_64\\\",\\\"build_info\\\":\\\"(local build)\\\",\\\"argv\\\":[\\\"smartctl\\\",\\\"--xall\\\",\\\"--json=c\\\",\\\"/dev/sr0\\\"],\\\"exit_status\\\":4},\\\"device\\\":{\\\"name\\\":\\\"/dev/sr0\\\",\\\"info_name\\\":\\\"/dev/sr0\\\",\\\"type\\\":\\\"scsi\\\",\\\"protocol\\\":\\\"SCSI\\\"},\\\"vendor\\\":\\\"QEMU\\\",\\\"product\\\":\\\"QEMU DVD-ROM\\\",\\\"model_name\\\":\\\"QEMU QEMU DVD-ROM\\\",\\\"revision\\\":\\\"2.5+\\\",\\\"scsi_version\\\":\\\"SPC-3\\\",\\\"device_type\\\":{\\\"scsi_value\\\":5,\\\"name\\\":\\\"CD/DVD\\\"},\\\"local_time\\\":{\\\"time_t\\\":1631746645,\\\"asctime\\\":\\\"Wed Sep 15 22:57:25 2021 UTC\\\"},\\\"temperature\\\":{\\\"current\\\":0,\\\"drive_trip\\\":0}}\",\"vendor\":\"QEMU\"},{\"by_path\":\"/dev/disk/by-path/pci-0000:00:05.0\",\"drive_type\":\"HDD\",\"id\":\"/dev/disk/by-path/pci-0000:00:05.0\",\"installation_eligibility\":{\"eligible\":true,\"not_eligible_reasons\":null},\"name\":\"vda\",\"path\":\"/dev/vda\",\"size_bytes\":130000000000,\"smart\":\"{\\\"json_format_version\\\":[1,0],\\\"smartctl\\\":{\\\"version\\\":[7,1],\\\"svn_revision\\\":\\\"5022\\\",\\\"platform_info\\\":\\\"x86_64-linux-4.18.0-305.10.2.el8_4.x86_64\\\",\\\"build_info\\\":\\\"(local build)\\\",\\\"argv\\\":[\\\"smartctl\\\",\\\"--xall\\\",\\\"--json=c\\\",\\\"/dev/vda\\\"],\\\"messages\\\":[{\\\"string\\\":\\\"/dev/vda: Unable to detect device type\\\",\\\"severity\\\":\\\"error\\\"}],\\\"exit_status\\\":1}}\",\"vendor\":\"0x1af4\"}],\"gpus\":[{\"address\":\"0000:00:02.0\",\"device_id\":\"00b8\",\"name\":\"GD 5446\",\"vendor\":\"Cirrus Logic\",\"vendor_id\":\"1013\"}],\"hostname\":\"ocp4-master0.ocpd.lab.local\",\"interfaces\":[{\"flags\":[\"up\",\"broadcast\",\"multicast\"],\"has_carrier\":true,\"ipv4_addresses\":[\"192.167.124.12/24\"],\"ipv6_addresses\":[],\"mac_address\":\"aa:bb:cc:11:42:10\",\"mtu\":1500,\"name\":\"ens3\",\"product\":\"0x0001\",\"speed_mbps\":-1,\"vendor\":\"0x1af4\"}],\"memory\":{\"physical_bytes\":33554432000,\"physical_bytes_method\":\"dmidecode\",\"usable_bytes\":32920096768},\"routes\":[{\"destination\":\"0.0.0.0\",\"family\":2,\"gateway\":\"192.167.124.1\",\"interface\":\"ens3\"},{\"destination\":\"10.88.0.0\",\"family\":2,\"interface\":\"cni-podman0\"},{\"destination\":\"192.167.124.0\",\"family\":2,\"interface\":\"ens3\"},{\"destination\":\"::1\",\"family\":10,\"interface\":\"lo\"},{\"destination\":\"fe80::\",\"family\":10,\"interface\":\"ens3\"},{\"destination\":\"fe80::\",\"family\":10,\"interface\":\"cni-podman0\"}],\"system_vendor\":{\"manufacturer\":\"Red Hat\",\"product_name\":\"KVM\",\"virtual\":true},\"timestamp\":1631746646,\"tpm_version\":\"none\"}",
    "kind": "Host",
    "logs_collected_at": "0001-01-01T00:00:00.000Z",
    "logs_started_at": "0001-01-01T00:00:00.000Z",
    "ntp_sources": "[{\"source_name\":\"funky.f5s.de\",\"source_state\":\"unreachable\"},{\"source_name\":\"ntp0.rrze.ipv6.uni-erlangen.de\",\"source_state\":\"unreachable\"},{\"source_name\":\"newkosh.ganneff.de\",\"source_state\":\"unreachable\"},{\"source_name\":\"195.50.171.101\",\"source_state\":\"unreachable\"},{\"source_name\":\"mail.deva-ayurveda.eu\",\"source_state\":\"unreachable\"},{\"source_name\":\"tunnel512919-pt.tunnel.tserv23.zrh1.ipv6.he.net\",\"source_state\":\"unreachable\"},{\"source_name\":\"dc8wan.de\",\"source_state\":\"unreachable\"},{\"source_name\":\"henry.22pf.org\",\"source_state\":\"unreachable\"},{\"source_name\":\"ntp2.hetzner.de\",\"source_state\":\"synced\"},{\"source_name\":\"ntp1.hetzner.de\",\"source_state\":\"not_combined\"}]",
    "progress": {
      "current_stage": "",
      "stage_started_at": "0001-01-01T00:00:00.000Z",
      "stage_updated_at": "0001-01-01T00:00:00.000Z"
    },
    "progress_stages": null,
    "role": "auto-assign",
    "stage_started_at": "0001-01-01T00:00:00.000Z",
    "stage_updated_at": "0001-01-01T00:00:00.000Z",
    "status": "known",
    "status_info": "Host is ready to be installed",
    "status_updated_at": "2021-09-15T19:24:42.938Z",
    "updated_at": "2021-09-15T22:57:35.116Z",
    "user_name": "admin",
    "validations_info": "{\"hardware\":[{\"id\":\"has-inventory\",\"status\":\"success\",\"message\":\"Valid inventory exists for the host\"},{\"id\":\"has-min-cpu-cores\",\"status\":\"success\",\"message\":\"Sufficient CPU cores\"},{\"id\":\"has-min-memory\",\"status\":\"success\",\"message\":\"Sufficient minimum RAM\"},{\"id\":\"has-min-valid-disks\",\"status\":\"success\",\"message\":\"Sufficient disk capacity\"},{\"id\":\"has-cpu-cores-for-role\",\"status\":\"success\",\"message\":\"Sufficient CPU cores for role auto-assign\"},{\"id\":\"has-memory-for-role\",\"status\":\"success\",\"message\":\"Sufficient RAM for role auto-assign\"},{\"id\":\"hostname-unique\",\"status\":\"success\",\"message\":\"Hostname ocp4-master0.ocpd.lab.local is unique in cluster\"},{\"id\":\"hostname-valid\",\"status\":\"success\",\"message\":\"Hostname ocp4-master0.ocpd.lab.local is allowed\"},{\"id\":\"valid-platform\",\"status\":\"success\",\"message\":\"Platform KVM is allowed\"},{\"id\":\"sufficient-installation-disk-speed\",\"status\":\"success\",\"message\":\"Speed of installation disk has not yet been measured\"},{\"id\":\"compatible-with-cluster-platform\",\"status\":\"success\",\"message\":\"Host is compatible with cluster platform baremetal\"}],\"network\":[{\"id\":\"connected\",\"status\":\"success\",\"message\":\"Host is connected\"},{\"id\":\"machine-cidr-defined\",\"status\":\"success\",\"message\":\"Machine Network CIDR is defined\"},{\"id\":\"belongs-to-machine-cidr\",\"status\":\"success\",\"message\":\"Host belongs to all machine network CIDRs\"},{\"id\":\"belongs-to-majority-group\",\"status\":\"success\",\"message\":\"Host has connectivity to the majority of hosts in the cluster\"},{\"id\":\"ntp-synced\",\"status\":\"success\",\"message\":\"Host NTP is synced\"},{\"id\":\"container-images-available\",\"status\":\"success\",\"message\":\"All required container images were either pulled successfully or no attempt was made to pull them\"},{\"id\":\"sufficient-network-latency-requirement-for-role\",\"status\":\"success\",\"message\":\"Network latency requirement has been satisfied.\"},{\"id\":\"sufficient-packet-loss-requirement-for-role\",\"status\":\"success\",\"message\":\"Packet loss requirement has been satisfied.\"},{\"id\":\"has-default-route\",\"status\":\"success\",\"message\":\"Host has been configured with at least one default route.\"},{\"id\":\"api-domain-name-resolved-correctly\",\"status\":\"success\",\"message\":\"Domain name resolution is not required (managed networking)\"},{\"id\":\"api-int-domain-name-resolved-correctly\",\"status\":\"success\",\"message\":\"Domain name resolution is not required (managed networking)\"},{\"id\":\"apps-domain-name-resolved-correctly\",\"status\":\"success\",\"message\":\"Domain name resolution is not required (managed networking)\"},{\"id\":\"dns-wildcard-not-configured\",\"status\":\"success\",\"message\":\"DNS wildcard check was successful\"}],\"operators\":[{\"id\":\"cnv-requirements-satisfied\",\"status\":\"success\",\"message\":\"cnv is disabled\"},{\"id\":\"lso-requirements-satisfied\",\"status\":\"success\",\"message\":\"lso is disabled\"},{\"id\":\"ocs-requirements-satisfied\",\"status\":\"success\",\"message\":\"ocs is disabled\"}]}"
   }
   ```
   This is a truncated version of the full ouput as it contains quite a lot of informations. Basically the agent provides all hardware infos to the assisted service so it can have a precise inventory of the host hardware and eventually validate the nodes.
   To get more infos about validation and hardware inventory, you can use those 2 one liners
     ```bash
     curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true" -H "accept: application/json" \
    -H "get_unregistered_clusters: false"| jq -r '.[].validations_info'|jq .
     ```

     ```bash
     curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true" -H "accept: application/json" \
     -H "get_unregistered_clusters: false"| jq -r '.[].hosts[].inventory'|jq -r .
     ```


   One important point to notice is that each hosts gets its own id after this process. We can extract these with the following call:
   ```bash
   [root@kvm-host ~] curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true"\
   -H "accept: application/json" -H "get_unregistered_clusters: false"| jq -r '.[].hosts[].id'

   2121a000-d27e-4596-a408-6813d3114caf
   84083091-8c0c-470b-a157-d002dbeed785
   fa89d7cd-c2d9-4f26-bd78-155647a32b04

   ```
- Assign role to discovered Nodes
 After validation, each node gets the  'auto-assign' role. We can check with  this API call:
    ```bash
  [root@kvm-host ~]# curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true" -H "accept:    application/json" -H "get_unregistered_clusters: false"| jq -r '.[].hosts[].role'
  auto-assign
  auto-assign
  auto-assign
   ```
  If you want something a bit more predictable, you  can assign roles based on nodes id. Since only our master nodes have been discovered, we will assign them the master role:


   ```bash
   for i in `curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true"\
     -H "accept: application/json" -H "get_unregistered_clusters: false"| jq -r '.[].hosts[].id'| awk 'NR>0' |awk '{print $1;}'`
   do curl -X PATCH "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID" -H "accept: application/json" -H "Content-Type: application/json" -d "{ \"hosts_roles\": [ { \"id\": \"$i\", \"role\": \"master\" } ]}"
   done

   ```
  Check the result:
   ```bash
  [root@kvm-host ~]# curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true"\
  -H "accept: application/json" \
   -H "get_unregistered_clusters: false"| jq -r '.[].hosts[].role'
  master
  master
  master
   ```
 - Add workers, complete configuration and trigger the installation

   It's now time to start our workers. The same discovery process will take place and the new nodes will get the **auto-assign** role. Because a cluster cannot have more than 3 masters, we are sure **auto-assign=worker** this time.
  Because we set **vip_dhcp_allocation** to  **false** in the cluster definition filer, we need to set **api_vip** parameter before we can trigger the installation.
   ```bash
    curl -X PATCH "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID" \
    -H "accept: application/json"\
    -H "Content-Type: application/json" -d "{ \"api_vip\": \"192.167.124.7\"}"

   ```
     And finally start installation:

   ```bash
     curl -X PATCH "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID" \
     -H "accept: application/json" \
     -H "Content-Type: application/json" -d "{ \"api_vip\": \"192.167.124.7\"}"
    ```
   During the installation process, disks will be written and nodes will reboot. One of the masters will also play the bootstrap role until the control plane is ready then the installation will continue as usual.




- Monitoring the installation progress
We can closely monitor the nodes states during the installation process:
  ```bash
  [root@kvm-host ~]# curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true"\
   -H "accept: application/json" \
   -H "get_unregistered_clusters: false"| jq -r '.[].hosts[].progress'
  {
    "current_stage": "Writing image to disk",
    "installation_percentage": 42,
    "progress_info": "92%",
    "stage_started_at": "2021-09-16T15:56:39.275Z",
    "stage_updated_at": "2021-09-16T15:57:31.215Z"
  }
  {
    "current_stage": "Writing image to disk",
    "installation_percentage": 42,
    "progress_info": "93%",
    "stage_started_at": "2021-09-16T15:56:38.290Z",
    "stage_updated_at": "2021-09-16T15:57:31.217Z"
  }
  {
    "current_stage": "Writing image to disk",
    "installation_percentage": 30,
    "progress_info": "92%",
    "stage_started_at": "2021-09-16T15:56:38.698Z",
    "stage_updated_at": "2021-09-16T15:57:31.218Z"
  }
  {
    "current_stage": "Waiting for control plane",
    "installation_percentage": 44,
    "stage_started_at": "2021-09-16T15:56:32.053Z",
    "stage_updated_at": "2021-09-16T15:56:32.053Z"
  }
  {
    "current_stage": "Waiting for control plane",
    "installation_percentage": 44,
    "stage_started_at": "2021-09-16T15:56:42.398Z",
    "stage_updated_at": "2021-09-16T15:56:42.398Z"
  }

  ```
  To monitor the whole installation progress:
   ```bash
   [root@kvm-host ~]# curl -s -X GET "$AI_URL/api/assisted-install/v2/clusters?with_hosts=true" \
   -H "accept: application/json" \
   -H "get_unregistered_clusters: false"| jq -r '.[].progress'
  {
    "finalizing_stage_percentage": 100,
    "installing_stage_percentage": 100,
    "preparing_for_installation_stage_percentage": 100,
    "total_percentage": 100
  }

   ```
- Retrieve kubeconfig and credentials
  ```bash
  [root@kvm-host ~]curl -X GET "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID/downloads/kubeconfig" -H "accept: application/octet-stream" > .kube/config
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  100 12104  100 12104    0     0  2955k      0 --:--:-- --:--:-- --:--:-- 2955k
  [root@kvm-host ~]oc get nodes
  NAME                          STATUS   ROLES    AGE    VERSION
  ocp4-master0.ocpd.lab.local   Ready    master   119m   v1.21.1+9807387
  ocp4-master1.ocpd.lab.local   Ready    master   134m   v1.21.1+9807387
  ocp4-master2.ocpd.lab.local   Ready    master   134m   v1.21.1+9807387
  ocp4-worker0.ocpd.lab.local   Ready    worker   119m   v1.21.1+9807387
  ocp4-worker1.ocpd.lab.local   Ready    worker   119m   v1.21.1+9807387

  ```

  ```bash
  [root@kvm-host ~]# curl -X GET "$AI_URL/api/assisted-install/v1/clusters/$CLUSTER_ID/credentials" -H "accept: application/json" |jq -r .
    % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                   Dload  Upload   Total   Spent    Left  Speed
  100   132  100   132    0     0  44000      0 --:--:-- --:--:-- --:--:-- 44000
  {
    "console_url": "https://console-openshift-console.apps.ocpd.lab.local",
    "password": "8Tepe-uxF7Q-ztHg5-yoKPQ",
    "username": "kubeadmin"
  }
  ```  
## Part III : Day 2 Operations
####  1. Adding worker nodes
Coming Soon .....

### Thank you for reading
* References
  * https://generator.swagger.io/?url=https://raw.githubusercontent.com/openshift/assisted-service/master/swagger.yaml
  * https://github.com/sonofspike/assisted-service-onprem
  * https://schmaustech.blogspot.com/2021/08/deploying-single-node-openshift-via.html
  * https://cloudcult.dev/cilium-installation-openshift-assisted-installer/
  * https://github.com/karmab/assisted-installer-cli
  * https://github.com/rh-telco-tigers/Assisted-Installer-API
