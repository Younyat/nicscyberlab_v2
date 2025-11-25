resource "openstack_compute_flavor_v2" "tiny" {
  name  = "tiny"
  vcpus = 1
  ram   = 512
  disk  = 5
}

resource "openstack_compute_flavor_v2" "small" {
  name  = "small"
  vcpus = 1
  ram   = 1024
  disk  = 10
}

resource "openstack_compute_flavor_v2" "medium" {
  name  = "medium"
  vcpus = 2
  ram   = 2048
  disk  = 20
}

resource "openstack_compute_flavor_v2" "large" {
  name  = "large"
  vcpus = 4
  ram   = 4096
  disk  = 40
}
