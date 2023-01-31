##############################################################################
## ICD Mongo
##############################################################################
resource "ibm_database" "icd_mongo" {
  name              = format("%s-%s", var.prefix, "mongo")
  service           = "databases-for-mongodb"
  plan              = var.icd_mongo_plan
  version           = var.icd_mongo_db_version
  service_endpoints = var.icd_mongo_service_endpoints
  location          = var.region
  resource_group_id = local.resource_group_id
  tags              = var.tags

  # Encrypt DB (comment to use IBM-provided Automatic Key)
  key_protect_instance      = ibm_resource_instance.key-protect.id
  key_protect_key           = ibm_kms_key.key.id
  backup_encryption_key_crn = ibm_kms_key.key.id
  depends_on = [ # require when using encryption key otherwise provisioning failed
    ibm_iam_authorization_policy.mongo-kms,
  ]

  # DB Settings
  adminpassword = var.icd_mongo_adminpassword
  group {
    group_id = "member"

    memory {
      allocation_mb = 1024
    }

    disk {
      allocation_mb = 20480
    }

    cpu {
      allocation_count = 0
    }
  }

  # auto_scaling {
  #   cpu {
  #     rate_increase_percent       = 20
  #     rate_limit_count_per_member = 20
  #     rate_period_seconds         = 900
  #     rate_units                  = "count"
  #   }
  #   disk {
  #     capacity_enabled             = true
  #     free_space_less_than_percent = 15
  #     io_above_percent             = 85
  #     io_enabled                   = true
  #     io_over_period               = "15m"
  #     rate_increase_percent        = 15
  #     rate_limit_mb_per_member     = 3670016
  #     rate_period_seconds          = 900
  #     rate_units                   = "mb"
  #   }
  #   memory {
  #     io_above_percent         = 90
  #     io_enabled               = true
  #     io_over_period           = "15m"
  #     rate_increase_percent    = 10
  #     rate_limit_mb_per_member = 114688
  #     rate_period_seconds      = 900
  #     rate_units               = "mb"
  #   }
  # }

  # users {
  #   name     = "user123"
  #   password = "password12"
  # }
  # whitelist {
  #   address     = "172.168.1.1/32"
  #   description = "desc"
  # }
}

## IAM
##############################################################################
# Doc at https://cloud.ibm.com/docs/cloud-databases?topic=cloud-databases-iam
resource "ibm_iam_access_group_policy" "iam-dbaas" {
  access_group_id = ibm_iam_access_group.accgrp.id
  roles           = ["Editor"]

  resources {
    service           = "databases-for-postgresql"
    resource_group_id = local.resource_group_id
  }
}

## VPE (Optional)
##############################################################################
# VPE can only be created once Mongo DB is fully registered in the backend
resource "time_sleep" "wait_for_mongo_initialization" {
  # count = tobool(var.use_vpe) ? 1 : 0

  depends_on = [
    ibm_database.icd_mongo
  ]

  create_duration = "5m"
}

# VPE (Virtual Private Endpoint) for Mongo
##############################################################################
# Make sure your Cloud Databases deployment's private endpoint is enabled
# otherwise you'll face this error: "Service does not support VPE extensions."
##############################################################################
resource "ibm_is_virtual_endpoint_gateway" "vpe_mongo" {
  name           = "${var.prefix}-mongo-vpe"
  resource_group = local.resource_group_id
  vpc            = ibm_is_vpc.vpc.id

  target {
    crn           = ibm_database.icd_mongo.id
    resource_type = "provider_cloud_service"
  }

  # one Reserved IP for per zone in the VPC
  dynamic "ips" {
    for_each = { for subnet in ibm_is_subnet.subnet : subnet.id => subnet }
    content {
      subnet = ips.key
      name   = "${ips.value.name}-ip"
    }
  }

  depends_on = [
    time_sleep.wait_for_mongo_initialization
  ]

  tags = var.tags
}

data "ibm_is_virtual_endpoint_gateway_ips" "mongo_vpe_ips" {
  gateway = ibm_is_virtual_endpoint_gateway.vpe_mongo.id
}

# output "mongo_vpe_ips" {
#   value = data.ibm_is_virtual_endpoint_gateway_ips.mongo_vpe_ips
# }


# Variables
##############################################################################
variable "icd_mongo_plan" {
  type        = string
  description = "The plan type of the Database instance"
  default     = "standard"
}
variable "icd_mongo_adminpassword" {
  type        = string
  description = "The admin user password for the instance"
  default     = "Passw0rd01"
}
variable "icd_mongo_db_version" {
  default     = "4.4"
  type        = string
  description = "The database version to provision if specified"
}
variable "icd_mongo_users" {
  default     = null
  type        = set(map(string))
  description = "Database Users. It is set of username and passwords"
}
variable "icd_mongo_whitelist" {
  default     = null
  type        = set(map(string))
  description = "Database Whitelist It is set of IP Address and description"
}
variable "icd_mongo_service_endpoints" {
  default     = "public"
  type        = string
  description = "Types of the service endpoints. Possible values are 'public', 'private', 'public-and-private'."
}