terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}
# instance the provider
provider "libvirt" {
   uri = "qemu:///system"
}
resource "libvirt_pool" "images" {
  name = "images"
  type = "dir"
  path = "/var/lib/libvirt/images"
}
resource "libvirt_network" "ocp_network" {
  name = "ocp4-net"
  mode = "nat"
  autostart = true
  domain = "lab.local"
  addresses = ["192.167.124.0/24"]
  bridge = "virbr-ocp4"
  dhcp {
        enabled = false
        }
}
