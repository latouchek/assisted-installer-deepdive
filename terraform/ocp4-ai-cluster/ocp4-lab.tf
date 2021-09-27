terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}
provider "libvirt" {
  uri = "qemu:///system"
}
# resource "libvirt_network" "ocp_network" {
#   name = "ocp4-net"
#   mode = "nat"
#   autostart = true
#   domain = "lab.local"
#   addresses = ["192.167.124/24"]
#   bridge = "virbr-ocp4"
#   dhcp {
#         enabled = false
#         }
# }

variable "worker" {
    type = list(string)
    default = ["ocp4-worker1", "ocp4-worker2","ocp4-worker3"]
  }
variable "master" {
     type = list(string)
     default = ["ocp4-master1", "ocp4-master2","ocp4-master3"]
   }

variable "worker-ht" {
    type = list(string)
    default = ["ocp4-worker1-ht"]
  }
####workers
resource "libvirt_volume" "fatdisk-workers" {
  name           = "fatdisk-${element(var.worker, count.index)}"
  pool           = "images"
  size           = 130000000000
  count = "${length(var.worker)}"
}
resource "libvirt_volume" "volume-mon-workers" {
  name   = "volume-mon-${element(var.worker, count.index)}"
  pool   = "images"
  size   = "30000000000"
  format = "qcow2"
  count = "${length(var.worker)}"
}
resource "libvirt_volume" "volume-osd1-workers" {
  name   = "volume-osd1-${element(var.worker, count.index)}"
  pool   = "images"
  size   = "30000000000"
  format = "qcow2"
  count = "${length(var.worker)}"
}
resource "libvirt_volume" "volume-osd2-workers" {
  name   = "volume-osd2-${element(var.worker, count.index)}"
  pool   = "images"
  size   = "30000000000"
  format = "qcow2"
  count = "${length(var.worker)}"
}
resource "libvirt_domain" "workers" {
  name   = "${element(var.worker, count.index)}"
  memory = "32000"
  vcpu   = 8
  cpu  = {
  mode = "host-passthrough"
  }
  running = false
  boot_device {
      dev = ["hd","cdrom"]
    }
  network_interface {
    network_name = "ocp4-net"
    mac = "AA:BB:CC:11:42:2${count.index}"
  }
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  disk {
    volume_id = "${element(libvirt_volume.fatdisk-workers.*.id, count.index)}"
  }
  disk {
      file = "/var/lib/libvirt/images/default/discovery_image_ocpd.iso"
    }
  disk {
    volume_id = "${element(libvirt_volume.volume-mon-workers.*.id, count.index)}"
  }
  disk {
    volume_id = "${element(libvirt_volume.volume-osd1-workers.*.id, count.index)}"
  }
  disk {
    volume_id = "${element(libvirt_volume.volume-osd2-workers.*.id, count.index)}"
  }
  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
  count = "${length(var.worker)}"
  # depends_on = [
  #   libvirt_network.ocp_network,
  # ]
}
####workers-ht###
resource "libvirt_volume" "fatdisk-worker-ht" {
  # name           = "fatdisk-${element(var.worker, count.index)}"
  name           = "fatdisk-${element(var.worker-ht, count.index)}"
  pool           = "images"
  size           = 130000000000
  count = "${length(var.worker-ht)}"
}
resource "libvirt_domain" "worker-ht" {
  name   = "${element(var.worker-ht, count.index)}"
  memory = "32000"
  vcpu   = 8
  cpu  = {
  mode = "host-passthrough"
  }
  running = false
  boot_device {
      dev = ["hd","cdrom"]
    }
  network_interface {
    network_name = "ocp4-net"
    mac = "AA:BB:CC:11:42:3${count.index}"
  }
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  disk {
    volume_id = "${element(libvirt_volume.fatdisk-worker-ht.*.id, count.index)}"
  }
  disk {
      file = "/var/lib/libvirt/images/default/discovery_image_ocpd.iso"
    }
  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
  count = "${length(var.worker-ht)}"
  # depends_on = [
  #   libvirt_network.ocp_network,
  # ]
}

####masters
resource "libvirt_volume" "fatdisk-masters" {
  # name           = "fatdisk-${element(var.master, count.index)}"
  name           = "fatdisk-${element(var.master, count.index)}"
  pool           = "images"
  size           = 130000000000
  count = "${length(var.master)}"
}


resource "libvirt_domain" "masters" {
  name   = "${element(var.master, count.index)}"
  memory = "32000"
  vcpu   = 12
  cpu = {
  mode = "host-passthrough"
  }
  running = true
  boot_device {
      dev = ["hd","cdrom"]
    }
  network_interface {
    network_name = "ocp4-net"
    mac = "AA:BB:CC:11:42:1${count.index}"
  }
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  disk {
    volume_id = "${element(libvirt_volume.fatdisk-masters.*.id, count.index)}"
  }
  disk {
      file = "/var/lib/libvirt/images/default/discovery_image_ocpd.iso"
    }
  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
  count = "${length(var.master)}"
  # depends_on = [
  #   libvirt_network.ocp_network,
  # ]
}
