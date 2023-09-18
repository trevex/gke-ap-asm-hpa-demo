terraform {
  backend "gcs" {
    bucket = "nvoss-gke-ap-asm-hpa-demo-tf-state"
    prefix = "terraform/cluster-0"
  }
}

provider "google" {
  project = var.project
  region  = var.region
}

provider "google-beta" {
  project = var.project
  region  = var.region
}

# Enable required APIs

resource "google_project_service" "services" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com", # required by terraform
    "compute.googleapis.com",
    "container.googleapis.com",
    "gkehub.googleapis.com",
    "anthos.googleapis.com",
    "mesh.googleapis.com",
    "meshca.googleapis.com",
    "meshconfig.googleapis.com",
  ])
  project = var.project
  service = each.value
}

# The underlying network mainly for the cluster

module "network" {
  source = "../modules//network"

  name = "mynetwork"
  subnetworks = [{
    name_affix    = "main" # full name will be `${name}-${name_affix}-${region}`
    ip_cidr_range = "10.0.0.0/20"
    region        = var.region
    secondary_ip_range = [{ # Use larger ranges in production!
      range_name    = "pods"
      ip_cidr_range = "10.0.32.0/19"
      }, {
      range_name    = "services"
      ip_cidr_range = "10.0.16.0/20"
    }]
  }]

  depends_on = [google_project_service.services]
}


# Create GKE Autopilot cluster

module "cluster" {
  source = "../modules//cluster"

  name                   = "mycluster"
  project                = var.project
  region                 = var.region
  network_id             = module.network.id
  subnetwork_id          = module.network.subnetworks["mynetwork-main-${var.region}"].id
  master_ipv4_cidr_block = "172.16.0.0/28"

  depends_on = [module.network]
}

# Register cluster to fleet

resource "google_gke_hub_membership" "membership" {
  project       = var.project
  membership_id = "mycluster"
  endpoint {
    gke_cluster {
      resource_link = "//container.googleapis.com/${module.cluster.id}"
    }
  }
  # authority {
  #   issuer = "https://container.googleapis.com/v1/${module.cluster.id}"
  # }
}

# Let's enable ASM and register our cluster to the fleet

resource "google_gke_hub_feature" "asm" {
  name     = "servicemesh"
  location = "global"

  depends_on = [google_project_service.services]
}

resource "google_gke_hub_feature_membership" "asm_member" {
  location   = "global"
  feature    = google_gke_hub_feature.asm.name
  membership = google_gke_hub_membership.membership.membership_id
  mesh {
    management = "MANAGEMENT_AUTOMATIC"
  }
}
