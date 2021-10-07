#!/bin/bash
TERRAVERSION=1.0.7 ####change me if needed
dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
dnf install -y libvirt libvirt-devel qemu-kvm mkisofs python3-devel jq ipmitool  git make bash-completion \
  net-tools  wget syslinux libvirt-libs tmux  \
  tar unzip go ipmitool virt-install libguestfs libguestfs-tools libguestfs-xfs net-tools  virt-what nmap
dnf group install "Development Tools" -y
systemctl enable --now libvirtd
wget https://releases.hashicorp.com/terraform/${TERRAVERSION}/terraform_${TERRAVERSION}_linux_amd64.zip
unzip terraform_${TERRAVERSION}_linux_amd64.zip
mv terraform /usr/local/sbin/
rm -f *zip

sed -i 's/^#   StrictHostKeyChecking ask/StrictHostKeyChecking no/g' /etc/ssh/ssh_config
echo "UserKnownHostsFile=/dev/null" | sudo tee -a /etc/ssh/ssh_config > /dev/null
sed -i 's/#UseDNS yes/UseDNS no/g' /etc/ssh/sshd_config
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
setenforce 0
###create kvm pool and network###

terraform -chdir=/opt/terraform/pool-net init
terraform -chdir=/opt/terraform/pool-net apply -auto-approve
