##############################################
# 🌐 Proveedor de OpenStack (Generado automáticamente)
# Fuente: kolla-admin desde /etc/kolla/clouds.yaml
# Autor: Younes Assouyat
##############################################

terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.52.1"
    }
  }
  required_version = ">= 1.5.0"
}

provider "openstack" {
  auth_url    = "http://192.168.5.12:5000"
  tenant_name = "admin"
  user_name   = "admin"
  password    = "SYm2HzC9IgRgWYwiZVoIeJWpAaeTbVNkF7S5D8L1"
  domain_name = "Default"
  region      = "RegionOne"
}
