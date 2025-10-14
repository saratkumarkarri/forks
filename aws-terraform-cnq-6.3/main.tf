#MIT License

#Copyright (c) 2025 Qumulo, Inc.

#Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the Software), to deal 
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is 
# furnished to do so, subject to the following conditions:

#The above copyright notice and this permission notice shall be included in all 
#copies or substantial portions of the Software.

#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
#SOFTWARE.

# **** Version 6.3 ****

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_vpc" "selected" {
  id = var.aws_vpc_id
}

data "aws_vpc_endpoint" "s3_gateway" {
  vpc_id       = var.aws_vpc_id
  service_name = "com.amazonaws.${var.aws_region}.s3"
}

data "aws_ssm_parameter" "persistent-storage-bucket-arns" {
  name            = "/qumulo/${local.persistent_storage.deployment_unique_name}/bucket-arns"
  with_decryption = true
}

data "aws_ssm_parameter" "persistent-storage-bucket-names" {
  name            = "/qumulo/${local.persistent_storage.deployment_unique_name}/bucket-names"
  with_decryption = true
}

data "aws_ssm_parameter" "persistent-storage-bucket-region" {
  name            = "/qumulo/${local.persistent_storage.deployment_unique_name}/bucket-region"
  with_decryption = true
}

data "aws_ssm_parameter" "persistent-storage-bucket-uris" {
  name            = "/qumulo/${local.persistent_storage.deployment_unique_name}/bucket-uris"
  with_decryption = true
}

data "aws_ssm_parameter" "persistent-storage-soft-capacity-limit" {
  name            = "/qumulo/${local.persistent_storage.deployment_unique_name}/soft-capacity-limit"
  with_decryption = true
}


locals {
  #local variable for cleaner references in subsequent use
  deployment_unique_name = null_resource.name_lock.triggers.deployment_unique_name

  # Persistent-storage alias
  persistent_storage = var.persistent_storage_outputs

  #Paths and S3 prefixes for the provisioning module
  functions_path      = "${path.module}/modules/qprovisioner/functions/"
  functions_s3_prefix = "${var.s3_bucket_prefix}${local.deployment_unique_name}/functions/"
  scripts_path        = "${path.module}/modules/qprovisioner/scripts/"
  scripts_s3_prefix   = "${var.s3_bucket_prefix}${local.deployment_unique_name}/scripts/"
  state_s3_prefix     = "${var.s3_bucket_prefix}${local.deployment_unique_name}"

  #Path for the Qumulo cluster module
  cluster_scripts_path = "${path.module}/modules/qcluster/scripts/"

  #S3 prefix for the Qumulo installer and package, note no trailing slash to build an ARN later
  install_s3_prefix = "${var.s3_bucket_prefix}qumulo-core-install"

  #make lists for subnet IDs
  private_subnet_ids = tolist(split(",", replace(var.private_subnet_id, "/\\s*/", "")))
  nlb_subnet_ids     = var.q_nlb_override_subnet_id == null ? local.private_subnet_ids : tolist(split(",", replace(var.q_nlb_override_subnet_id, "/\\s*/", "")))

  #Get the list of S3 buckets, region, and max capacity from parameter store
  persistent_storage_bucket_arns    = nonsensitive(data.aws_ssm_parameter.persistent-storage-bucket-arns.value)
  persistent_storage_bucket_names   = nonsensitive(data.aws_ssm_parameter.persistent-storage-bucket-names.value)
  persistent_storage_bucket_region  = nonsensitive(data.aws_ssm_parameter.persistent-storage-bucket-region.value)
  persistent_storage_bucket_uris    = nonsensitive(data.aws_ssm_parameter.persistent-storage-bucket-uris.value)
  persistent_storage_capacity_limit = nonsensitive(data.aws_ssm_parameter.persistent-storage-soft-capacity-limit.value)

  #Logic to decide when to provision the R53 Resolver
  r53_rslvr_provision = var.second_private_subnet_id == null || var.q_cluster_fqdn == null || var.q_nlb_provision == true || module.qconfig.multi_az || var.q_replacement_cluster ? false : true
}

#Check for S3 Gateway in VPC
resource "null_resource" "check_s3_gateway" {
  count = data.aws_vpc_endpoint.s3_gateway.vpc_endpoint_type == "Gateway" && data.aws_vpc_endpoint.s3_gateway.state == "available" && length(data.aws_vpc_endpoint.s3_gateway.route_table_ids) > 0 ? 0 : "S3 Gateway not present for the chosen VPC.  Add an S3 Gateway."
}

#Generates a 11 digit random alphanumeric for the deployment_unique_name.  Generated on first apply and never changes.
resource "random_string" "alphanumeric" {
  length    = 11
  lower     = false
  min_upper = 4
  numeric   = true
  special   = false
  upper     = true
  keepers = {
    name = var.deployment_name
  }
  lifecycle { ignore_changes = all }
}

#This resource is used to 'lock' the deployment_unique_name.  Any changes to the deployment_name after the first apply are ignored.
#Appends the random alpha numeric to the deployment name.  All resources are tagged/named with this unique name.
resource "null_resource" "name_lock" {
  triggers = {
    deployment_unique_name = "${var.deployment_name}-${random_string.alphanumeric.id}"
  }

  lifecycle { ignore_changes = all }
}

#Copy files from the terraform local directory to the specified S3 bucket.  Unique S3 prefix per cluster.  Files will only be updated if the MD5 hash changes.
resource "aws_s3_object" "provisioner_functions" {
  provider    = aws.bucket
  for_each    = fileset(local.functions_path, "*")
  bucket      = var.s3_bucket_name
  key         = "${local.functions_s3_prefix}${each.value}"
  source      = "${local.functions_path}${each.value}"
  source_hash = filemd5("${local.functions_path}${each.value}")
}

resource "aws_s3_object" "provisioner_script" {
  provider    = aws.bucket
  for_each    = fileset(local.scripts_path, "provision.sh")
  bucket      = var.s3_bucket_name
  key         = "${local.scripts_s3_prefix}${each.value}"
  source      = "${local.scripts_path}${each.value}"
  source_hash = filemd5("${local.scripts_path}${each.value}")
}

#This sub-module stores Qumulo admin credentials in AWS Secrets Manager.
module "secrets" {
  source = "./modules/secrets"

  cluster_admin_password = var.q_cluster_admin_password
  deployment_unique_name = local.deployment_unique_name
}

#This sub-module validates and error checks subnets and AZ variables.  It establishes the final configuration variables for the cluster.
module "qconfig" {
  source = "./modules/qconfig"

  aws_region                       = var.aws_region
  persistent_storage_bucket_region = local.persistent_storage_bucket_region
  nlb_subnet_ids                   = local.nlb_subnet_ids
  node_count                       = var.q_node_count
  private_subnet_ids               = local.private_subnet_ids
  replacement_cluster              = var.q_replacement_cluster
  target_node_count                = var.q_target_node_count
}

#This sub-module builds the Qumulo Cluster consisting of EC2 instances, EBS volumes, and S3 buckets.
#A security group is built for the cluster and an IAM role is also built for the cluster.
module "qcluster" {
  source = "./modules/qcluster"

  ami_id                                    = var.q_ami_id
  aws_account_id                            = data.aws_caller_identity.current.account_id
  aws_number_azs                            = module.qconfig.number_azs
  aws_partition                             = data.aws_partition.current.partition
  aws_region                                = var.aws_region
  aws_vpc_id                                = var.aws_vpc_id
  boot_dkv_type                             = var.q_boot_dkv_type
  boot_drive_size                           = var.q_boot_drive_size
  cluster_additional_sg_ids                 = var.q_cluster_additional_sg_ids == null ? [] : tolist(split(",", replace(var.q_cluster_additional_sg_ids, "/\\s*/", "")))
  cluster_initial_floating_ips              = var.q_cluster_initial_floating_ips
  cluster_min_floating_ips_per_node         = var.q_cluster_min_floating_ips_per_node
  cluster_name                              = var.q_cluster_name
  cluster_scripts_path                      = local.cluster_scripts_path
  cluster_sg_cidrs                          = var.q_cluster_additional_sg_cidrs == null ? [data.aws_vpc.selected.cidr_block] : concat([data.aws_vpc.selected.cidr_block], tolist(split(",", replace(var.q_cluster_additional_sg_cidrs, "/\\s*/", ""))))
  cluster_persistent_storage_capacity_limit = local.persistent_storage_capacity_limit
  cluster_version                           = var.q_cluster_version
  debian_package                            = var.q_debian_package
  deployment_unique_name                    = local.deployment_unique_name
  ec2_key_pair                              = var.ec2_key_pair
  existing_deployment_unique_name           = var.q_existing_deployment_unique_name
  install_s3_prefix                         = local.install_s3_prefix
  instance_recovery_topic                   = var.q_instance_recovery_topic
  instance_type                             = (var.q_instance_type == "m6i.xlarge" || (var.q_instance_type == "m6idn.xlarge" || var.q_instance_type == "i4i.xlarge" || var.q_instance_type == "i7i.xlarge" || var.q_instance_type == "i7ie.xlarge" || var.q_instance_type == "i3en.xlarge") && !var.dev_environment) ? replace(var.q_instance_type, "/\\..*/", ".2xlarge") : var.q_instance_type
  kms_key_id                                = var.kms_key_id
  nlb_provision                             = var.q_nlb_provision
  node_count                                = var.q_node_count
  permissions_boundary                      = var.q_permissions_boundary
  persistent_bucket_arns                    = local.persistent_storage_bucket_arns
  private_subnet_ids                        = module.qconfig.private_subnet_id_per_node
  replacement_cluster                       = var.q_replacement_cluster
  require_imdsv2                            = true
  s3_bucket_name                            = var.s3_bucket_name
  s3_bucket_region                          = var.s3_bucket_region
  target_node_count                         = var.q_target_node_count
  term_protection                           = var.term_protection
  write_cache_iops                          = var.q_write_cache_iops
  write_cache_tput                          = var.q_write_cache_tput
  write_cache_type                          = var.q_write_cache_type

  tags = var.tags
}

#This sub-module instantiates an EC2 instance for configuration of the Qumulo Cluster and is then shutdown.  
#Floating IPs, admin password, EBS tags, termination protection, and S3 storage class are all configured.
#Until Terraform supports user data updates without destroying the instance, this instance will get destroyed
#and recreated on subsequent applies.  It is built for this as all state is stored in SSM Parameter Store.
module "qprovisioner" {
  source = "./modules/qprovisioner"

  ami_id                                    = var.q_ami_id
  aws_account_id                            = data.aws_caller_identity.current.account_id
  aws_number_azs                            = module.qconfig.number_azs
  aws_partition                             = data.aws_partition.current.partition
  aws_region                                = var.aws_region
  aws_vpc_id                                = var.aws_vpc_id
  check_provisioner_shutdown                = var.check_provisioner_shutdown
  cluster_additional_sg_ids                 = var.q_cluster_additional_sg_ids == null ? [] : tolist(split(",", replace(var.q_cluster_additional_sg_ids, "/\\s*/", "")))
  cluster_fault_domain_ids                  = module.qconfig.private_fault_domain_id_per_node
  cluster_floating_ips                      = module.qcluster.floating_ips
  cluster_fqdn                              = var.q_cluster_fqdn
  cluster_iam_role_arn                      = module.qcluster.iam_role_arn
  cluster_instance_ids                      = module.qcluster.instance_ids
  cluster_max_floating_ips                  = module.qcluster.max_floating_ips
  cluster_name                              = var.q_cluster_name
  cluster_node1_ip                          = module.qcluster.node1_ip
  cluster_persistent_bucket_uris            = local.persistent_storage_bucket_uris
  cluster_persistent_bucket_arns_json       = module.qcluster.persistent_bucket_arns_json
  cluster_persistent_bucket_arns            = module.qcluster.persistent_bucket_arns
  cluster_persistent_bucket_names           = local.persistent_storage_bucket_names
  cluster_persistent_bucket_policy          = var.q_persistent_storage_bucket_policy
  cluster_persistent_storage_type           = var.q_persistent_storage_type
  cluster_persistent_storage_capacity_limit = local.persistent_storage_capacity_limit
  cluster_primary_ips                       = module.qcluster.primary_ips
  cluster_secrets_arn                       = module.secrets.cluster_secrets_arn
  cluster_sg_cidrs                          = var.q_cluster_additional_sg_cidrs == null ? [data.aws_vpc.selected.cidr_block] : concat([data.aws_vpc.selected.cidr_block], tolist(split(",", replace(var.q_cluster_additional_sg_cidrs, "/\\s*/", ""))))
  cluster_sg_id                             = module.qcluster.security_group_id
  cluster_temporary_password                = module.qcluster.temporary_password
  cluster_version                           = var.q_cluster_version
  debian_package                            = var.q_debian_package  
  deployment_unique_name                    = local.deployment_unique_name
  ec2_key_pair                              = var.ec2_key_pair
  ena_express                               = module.qcluster.ena_express
  existing_deployment_unique_name           = var.q_existing_deployment_unique_name
  boot_type                                 = var.q_boot_dkv_type
  flash_tput                                = module.qcluster.write_cache_tput == null ? 0 : module.qcluster.write_cache_tput
  flash_iops                                = module.qcluster.write_cache_iops == null ? 0 : module.qcluster.write_cache_iops
  functions_s3_prefix                       = local.functions_s3_prefix
  install_s3_prefix                         = local.install_s3_prefix
  instance_type                             = "m5.large"
  kms_key_id                                = var.kms_key_id
  kms_s3_arn                                = module.qcluster.kms_s3_arn
  permissions_boundary                      = var.q_permissions_boundary
  private_subnet_id                         = module.qconfig.private_subnet_id_per_node[0]
  replacement_cluster                       = var.q_replacement_cluster
  require_imdsv2                            = true
  s3_bucket_name                            = var.s3_bucket_name
  s3_bucket_region                          = var.s3_bucket_region
  scripts_path                              = local.scripts_path
  scripts_s3_prefix                         = local.scripts_s3_prefix
  target_node_count                         = var.q_target_node_count
  term_protection                           = var.term_protection
  tun_refill_IOPS                           = module.qcluster.refill_IOPS
  tun_refill_Bps                            = module.qcluster.refill_Bps
  tun_EBS_BW                                = module.qcluster.EBS_BW
  tun_EC2_BW                                = module.qcluster.EC2_BW
  tun_disk_count                            = module.qcluster.disk_count

  tags = var.tags
}

#This sub-module builds a Route 53 Resolver to forward q_cluster_fqdn DNS requests to the Qumulo cluster.
#The Qumulo cluster will then respond to DNS queries with floating IP addresses for clients to mount, providing load balancing and availability.
#It is only invoked if two private subnets have been provided in unique AZs for availability.
#It is also only applicable to single AZ clusters that are not using a load balancer.
#With this approach floating IP addresses no longer have to be maintained and updated in your chosen DNS solution.
module "route53-resolver" {
  count = local.r53_rslvr_provision ? 1 : 0

  source = "./modules/route53-resolver"

  aws_vpc_cidr             = data.aws_vpc.selected.cidr_block
  aws_vpc_id               = var.aws_vpc_id
  deployment_unique_name   = local.deployment_unique_name
  fqdn                     = var.q_cluster_fqdn
  private_subnet_id        = module.qconfig.private_subnet_id_per_node[0]
  second_private_subnet_id = var.second_private_subnet_id
  target_ips               = module.qcluster.floating_ips == [] ? [module.qcluster.primary_ips[0]] : slice(module.qcluster.floating_ips, 0, 3)

  tags = var.tags
}

#This module creates an AWS NLB in front of the Qumulo cluster for load distribution and fault tolerance.
#Floating IPs are disabled when using this module because DNS is no longer used for load distribution
#and floating IPs are no longer relevant for IP failover.  NLBs cost more $ and NFSv3 locking is not
#reliable through an NLB.  An NLB is optional for single AZ deployments and mandatory for multi-AZ
#deployments.
module "nlb-qumulo" {
  count = var.q_nlb_provision || module.qconfig.multi_az ? 1 : 0

  source = "./modules/nlb-qumulo"

  aws_vpc_id             = var.aws_vpc_id
  cluster_primary_ips    = module.qcluster.primary_ips
  cross_zone             = var.q_nlb_cross_zone
  deployment_unique_name = local.deployment_unique_name
  dereg_delay            = 60
  dereg_term             = false
  node_count             = var.q_node_count
  preserve_ip            = true
  private_subnet_ids     = module.qconfig.nlb_subnet_ids
  proxy_proto_v2         = false
  random_alphanumeric    = random_string.alphanumeric.id
  stickiness             = var.q_nlb_stickiness
  is_public              = var.dev_environment && !var.q_nlb_internal
  term_protection        = var.term_protection

  tags = var.tags
}
#This module creates resource groups for filtered views of EC2, EBS Write Cache, EBS DKV, and the S3 persistent store.
#It also creates a log group for Qumulo audit logs.
module "cloudwatch" {
  source = "./modules/cloudwatch"

  audit_logging          = var.q_audit_logging
  aws_region             = var.aws_region
  cluster_name           = var.q_cluster_name
  deployment_unique_name = local.deployment_unique_name

  tags = var.tags
}