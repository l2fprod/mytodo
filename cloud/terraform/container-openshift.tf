## IAM
##############################################################################
# Create a policy to all Kubernetes instances within the Resource Group
resource "ibm_iam_access_group_policy" "policy-k8s" {
  access_group_id = ibm_iam_access_group.accgrp.id
  roles           = ["Manager", "Writer", "Editor", "Operator", "Viewer"]

  resources {
    service           = "containers-kubernetes"
    resource_group_id = ibm_resource_group.resource_group.id
  }
}

# OpenShift Variables
##############################################################################

variable "openshift_cluster_name" {
  description = "Name of the cluster"
  type        = string
  default     = "roks"
}

variable "openshift_version" {
  description = "The OpenShift version that you want to set up in your cluster."
  type        = string
  default     = "4.12.3_openshift"
}

variable "openshift_machine_flavor" {
  description = " The flavor of the VPC worker node that you want to use."
  type        = string
  default     = "bx2.4x16"
}

variable "openshift_worker_nodes_per_zone" {
  description = "The number of worker nodes per zone in the default worker pool."
  type        = number
  default     = 1
}

variable "worker_labels" {
  description = "Labels on all the workers in the default worker pool."
  type        = map(any)
  default     = null
}

variable "openshift_wait_till" {
  description = "specify the stage when Terraform to mark the cluster creation as completed."
  type        = string
  default     = "OneWorkerNodeReady"

  validation {
    error_message = "`openshift_wait_till` value must be one of `MasterNodeReady`, `OneWorkerNodeReady`, or `IngressReady`."
    condition = contains([
      "MasterNodeReady",
      "OneWorkerNodeReady",
      "IngressReady"
    ], var.openshift_wait_till)
  }
}

variable "disable_public_service_endpoint" {
  description = "Boolean value true if Public service endpoint to be disabled."
  type        = bool
  default     = false
}

variable "openshift_force_delete_storage" {
  description = "force the removal of persistent storage associated with the cluster during cluster deletion."
  type        = bool
  default     = true
}

variable "kms_config" {
  type    = list(map(string))
  default = []
}

variable "entitlement" {
  description = "Enable openshift entitlement during cluster creation ."
  type        = string
  default     = "cloud_pak"
}

variable "openshift_update_all_workers" {
  description = "OpenShift version of the worker nodes is updated."
  type        = bool
  default     = true
}


## Resources
##############################################################################
resource "ibm_container_vpc_cluster" "cluster" {
  name              = format("%s-%s", var.prefix, var.openshift_cluster_name)
  vpc_id            = ibm_is_vpc.vpc.id
  resource_group_id = local.resource_group_id
  kube_version      = var.openshift_version
  cos_instance_crn  = var.is_openshift_cluster ? ibm_resource_instance.cos.id : null
  entitlement       = var.entitlement
  tags              = var.tags
  disable_public_service_endpoint = var.disable_public_service_endpoint
  update_all_workers = var.openshift_update_all_workers

  flavor            = var.openshift_worker_nodes_per_zone
  worker_count      = var.worker_count
  wait_till         = var.openshift_wait_till

  dynamic "zones" {
    for_each = { for subnet in ibm_is_subnet.subnet : subnet.id => subnet }
    content {
      name      = zones.value.zone
      subnet_id = zones.value.id
    }
  }

  kms_config = [
    {
      instance_id      = ibm_resource_instance.key-protect.guid, # GUID of Key Protect instance
      crk_id           = ibm_kms_key.key.key_id,                 # ID of customer root key
      private_endpoint = true
    }
  ]
}

# resource "null_resource" "cluster_wait" {
#   triggers = {
#     cluster_id = ibm_container_vpc_cluster.cluster.id
#   }
#   provisioner "local-exec" {
#     command = <<EOT
# sleep 120
# EOT
#   }
#   depends_on = [ibm_container_vpc_cluster.cluster]
# }

resource "ibm_container_vpc_worker_pool" "worker_pools" {
  for_each          = { for pool in var.worker_pools : pool.pool_name => pool }
  cluster           = ibm_container_vpc_cluster.cluster.id
  resource_group_id = local.resource_group_id
  worker_pool_name  = each.key
  flavor            = lookup(each.value, "machine_type", null)
  vpc_id            = ibm_is_vpc.vpc.id
  worker_count      = each.value.workers_per_zone

  dynamic "zones" {
    for_each = { for subnet in ibm_is_subnet.subnet : subnet.id => subnet }
    content {
      name      = zones.value.zone
      subnet_id = zones.value.id
    }
  }

#   depends_on = [null_resource.cluster_wait]
}


data "ibm_container_cluster_config" "cluster_config" {
  cluster_name_id   = ibm_container_vpc_cluster.cluster.id
  resource_group_id = ibm_resource_group.resource_group.id
}

resource "ibm_resource_instance" "openshift_cos_instance" {
  count             = var.is_openshift_cluster ? 1 : 0
  name              = join("-", [var.environment_id, "roks-backup"])
  resource_group_id = local.resource_group_id
  service           = "cloud-object-storage"
  plan              = "standard"
  location          = "global"
  tags              = var.tags
}
