##############################################
#  Infraestructura de Redes, Router y Seguridad en OpenStack
# Redes: red_privada y red_externa
# Router: router_privado
# Security Group: sg_wazuh_suricata
# Autor: Younes Assouyat
##############################################

# -----------------------------
#  Red Externa (Public/External)
# -----------------------------
resource "openstack_networking_network_v2" "red_externa" {
  name           = "red_externa"
  admin_state_up = true
  shared         = false
  external       = true
}

resource "openstack_networking_subnet_v2" "red_externa_subnet" {
  name            = "red_externa_subnet"
  network_id      = openstack_networking_network_v2.red_externa.id
  cidr            = "10.0.2.0/24"        #  Red física real (uplinkbridge)
  ip_version      = 4
  enable_dhcp     = false                 #  NO usar DHCP en red externa
  gateway_ip      = "10.0.2.1"            # Gateway del uplinkbridge
  dns_nameservers = ["8.8.8.8", "1.1.1.1"]
}

# -----------------------------
#  Red Privada
# -----------------------------
resource "openstack_networking_network_v2" "red_privada" {
  name           = "red_privada"
  admin_state_up = true
  shared         = false
}

resource "openstack_networking_subnet_v2" "red_privada_subnet" {
  name            = "red_privada_subnet"
  network_id      = openstack_networking_network_v2.red_privada.id
  cidr            = "192.168.100.0/24"
  ip_version      = 4
  enable_dhcp     = true
  gateway_ip      = "192.168.100.1"
  dns_nameservers = ["8.8.8.8", "1.1.1.1"]
}

# -----------------------------
#  Router Privado
# -----------------------------
resource "openstack_networking_router_v2" "router_privado" {
  name                = "router_privado"
  admin_state_up      = true
  external_network_id = openstack_networking_network_v2.red_externa.id
}

resource "openstack_networking_router_interface_v2" "router_privado_interface" {
  router_id = openstack_networking_router_v2.router_privado.id
  subnet_id = openstack_networking_subnet_v2.red_privada_subnet.id
}

# -----------------------------
#  Grupo de Seguridad Básico
# -----------------------------
resource "openstack_networking_secgroup_v2" "sg_wazuh_suricata" {
  name        = "sg_wazuh_suricata"
  description = "Reglas básicas: SSH, ICMP, HTTP, HTTPS"
}

#  SSH (Puerto 22)
resource "openstack_networking_secgroup_rule_v2" "ssh_in" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.sg_wazuh_suricata.id
}

#  ICMP (Ping)
resource "openstack_networking_secgroup_rule_v2" "icmp_in" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.sg_wazuh_suricata.id
}

#  HTTP (Puerto 80)
resource "openstack_networking_secgroup_rule_v2" "http_in" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.sg_wazuh_suricata.id
}

#  HTTPS (Puerto 443)
resource "openstack_networking_secgroup_rule_v2" "https_in" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.sg_wazuh_suricata.id
}

# -----------------------------
#  Salidas útiles
# -----------------------------
output "router_privado_info" {
  description = "Información del router y redes creadas"
  value = {
    router_name        = openstack_networking_router_v2.router_privado.name
    external_gateway   = openstack_networking_router_v2.router_privado.external_network_id
    internal_interface = openstack_networking_subnet_v2.red_privada_subnet.cidr
  }
}

output "sg_wazuh_suricata_info" {
  description = "Grupo de seguridad básico creado"
  value = openstack_networking_secgroup_v2.sg_wazuh_suricata.name
}
