#MIT License

#Copyright (c) 2025 Qumulo, Inc.

#Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the Software), to deal 
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is 
# furnished to do so, subject to the following conditions =

#The above copyright notice and this permission notice shall be included in all 
#copies or substantial portions of the Software.

#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
#SOFTWARE.

variable "aws_region" {
  description = "AWS region"
  type        = string
  nullable    = false
}
variable "aws_vpc_id" {
  description = "AWS VPC identifier"
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^vpc-", var.aws_vpc_id))
    error_message = "The aws_vpc_id must be a valid VPC ID of the form 'vpc-'."
  }
}
variable "check_provisioner_shutdown" {
  description = "Executes a local-exec script on the Terraform machine to check if the provisioner instance shutdown which indicates a successful cluster deployment."
  type        = bool
  default     = true
}
variable "deployment_name" {
  description = "Name for this Terraform deployment.  This name plus 11 random hex digits will be used for all resource names where appropriate."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9A-Za-z\\-]{2,32}$", var.deployment_name))
    error_message = "The deployment_name must be a <=32 characters long and use 0-9 A-Z a-z or dash (-)."
  }
}
variable "dev_environment" {
  description = "Enables the use of m5.xlarge instance type.  NOT recommended for production and overridden when not a development environment."
  type        = bool
  default     = false
}
variable "ec2_key_pair" {
  description = "AWS EC2 key pair"
  type        = string
  nullable    = false
}
variable "kms_key_id" {
  description = "OPTIONAL: AWS KMS encryption key identifier"
  type        = string
  default     = null
  validation {
    condition     = var.kms_key_id == null || can(regex("^[0-9A-Za-z]{8}[-][0-9A-Za-z]{4}[-][0-9A-Za-z]{4}[-][0-9A-Za-z]{4}[-][0-9A-Za-z]{12}$", var.kms_key_id))
    error_message = "The kms_key_id must be an alphanumeric value formated 12345678-1234-1234-1234-1234567890ab."
  }
}
variable "private_subnet_id" {
  description = "AWS private subnet identifier"
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^subnet-", var.private_subnet_id))
    error_message = "The private_subnet_id must be a valid Subnet ID of the form 'subnet-'."
  }
}
variable "q_ami_id" {
  description = "Qumulo AMI-ID or Ubuntu AMI-ID"
  type        = string
  default     = null
  validation {
    condition     = var.q_ami_id == null || can(regex("^ami-[0-9A-Za-z]{17}$", var.q_ami_id))
    error_message = "The q_ami_id must be a valid AMI ID of the form 'ami-0123456789abcdefg'."
  }
}
variable "q_audit_logging" {
  description = "OPTIONAL: Configure a CloudWatch Log group to store Audit logs from Qumulo"
  type        = bool
  default     = false
}
variable "q_boot_dkv_type" {
  description = "OPTIONAL: Specify the type of EBS for the boot drive and dkv drives"
  type        = string
  default     = "gp3"
  validation {
    condition = anytrue([
      var.q_boot_dkv_type == "gp2",
      var.q_boot_dkv_type == "gp3"
    ])
    error_message = "An invalid EBS flash type was specified. Must be gp2 or gp3."
  }
}
variable "q_boot_drive_size" {
  description = "Size of the boot drive for each Qumulo Instance"
  type        = number
  nullable    = false
  default     = 256
}
variable "q_provisioner_boot_size" {
  description = "Size (GB) of the provisioner root volume. Increase if the AMI snapshot requires more space."
  type        = number
  default     = 150
  validation {
    condition     = var.q_provisioner_boot_size >= 150
    error_message = "The provisioner root volume must be at least 150 GB to satisfy the AMI snapshot requirements."
  }
}
variable "q_cluster_additional_sg_cidrs" {
  description = "OPTIONAL: AWS additional security group CIDRs for the Qumulo cluster"
  type        = string
  default     = null
  validation {
    condition     = var.q_cluster_additional_sg_cidrs == null || can(regex("^(((([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\\/(3[0-2]|[1-2][0-9]|[0-9])))[,]\\s*)*((([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\\/(3[0-2]|[1-2][0-9]|[0-9])))$", var.q_cluster_additional_sg_cidrs))
    error_message = "The q_cluster_additional_sg_cidrs must be a valid comma delimited string of CIDRS of the form '10.0.1.0/24, 10.10.3.0/24, 172.16.30.0/24'."
  }
}
variable "q_cluster_additional_sg_ids" {
  description = "OPTIONAL: AWS additional security groups IDs for the Qumulo cluster"
  type        = string
  default     = null
  validation {
    condition     = var.q_cluster_additional_sg_ids == null || can(regex("^sg-", var.q_cluster_additional_sg_ids))
    error_message = "The q_cluster_additional_sg_ids must contain a valid Security group ID of the form 'sg-'."
  }
}
variable "q_cluster_initial_floating_ips" {
  description = "Qumulo initial number of floating IP addresses for the cluster"
  type        = number
  default     = 12
  validation {
    condition     = var.q_cluster_initial_floating_ips == 0 || var.q_cluster_initial_floating_ips >= 3 && var.q_cluster_initial_floating_ips <= 100
    error_message = "Specify 3 to 100 floating IPs for the starting size of the pool for single AZ clusters.  Default is 12. Set to 0 for no floating IPs (not recommended)."
  }
}
variable "q_cluster_min_floating_ips_per_node" {
  description = "Qumulo minimum floating IP addresses per node for single AZ clusters"
  type        = number
  default     = 1
  validation {
    condition = anytrue([
      var.q_cluster_min_floating_ips_per_node == 1,
      var.q_cluster_min_floating_ips_per_node == 2,
      var.q_cluster_min_floating_ips_per_node == 3,
      var.q_cluster_min_floating_ips_per_node == 4
    ])
    error_message = "Specify 1, 2, 3, or 4 minimum floating IPs per node for single AZ clusters.  Default is 1."
  }
}
variable "q_cluster_name" {
  description = "Qumulo cluster name"
  type        = string
  default     = "CNQ"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9\\-]{0,13}[a-zA-Z0-9]$", var.q_cluster_name))
    error_message = "The q_cluster_name must be an alphanumeric string between 2 and 15 characters. Dash (-) is allowed if not the first or last character."
  }
}
variable "q_cluster_version" {
  description = "Qumulo cluster software version"
  type        = string
  default     = "7.4.4"
  validation {
    condition     = can(regex("^((4\\.[2-3]\\.[0-9][0-9]?\\.?[0-9]?[0-9]?)|([5-9][0-9]?\\.[0-9]+\\.[0-9][a-zA-Z0-9]?\\.?[0-9]?[a-zA-Z0-9]?))$", var.q_cluster_version))
    error_message = "The q_cluster_version 7.0.1 or greater. Examples: 7.0.1, 7.0.2, 7.1.0."
  }
}
variable "q_cluster_admin_password" {
  description = "Qumulo cluster admin password"
  type        = string
  sensitive   = true
  nullable    = false
  validation {
    condition     = can(regex("^(.{0,7}|[^0-9]*|[^A-Z]*|[^a-z]*|[a-zA-Z0-9]*)$", var.q_cluster_admin_password)) ? false : true
    error_message = "The q_cluster_admin_password must be at least 8 characters and contain an uppercase, lowercase, number, and special character."
  }
}
variable "q_cluster_fqdn" {
  description = "Fully qualified domain name for Qumulo DNS"
  type        = string
  default     = null
  validation {
    condition     = var.q_cluster_fqdn == null || can(regex("^[a-z][a-z.-]*[a-z]$", var.q_cluster_fqdn))
    error_message = "The fqdn must use lowercase, start and end with letters only, and may contain . and -"
  }
}
variable "q_debian_package" {
  description = "Debian or RHL package"
  type        = bool
  default     = true
}
variable "q_existing_deployment_unique_name" {
  description = "OPTIONAL: The deployment_unique_name of the previous deployed cluster you want to replace"
  type        = string
  default     = null
  validation {
    condition     = var.q_existing_deployment_unique_name == null || can(regex("^[0-9A-Za-z\\-]{2,52}$", var.q_existing_deployment_unique_name))
    error_message = "The deployment_name must be a <=52 characters long and use 0-9 A-Z a-z or dash (-). Copy from previous deployment Terraform workspace output."
  }
}
#Do NOT change.  Not supported with Cloud.Next currently
variable "q_instance_recovery_topic" {
  description = "OPTIONAL: AWS SNS topic for Qumulo instance recovery"
  type        = string
  default     = null
}
variable "q_instance_type" {
  description = "Qumulo EC2 instance type"
  type        = string
  default     = "i4i.2xlarge"
  nullable    = false
  validation {
    condition = anytrue([
      var.q_instance_type == "m6idn.xlarge",
      var.q_instance_type == "m6idn.2xlarge",
      var.q_instance_type == "m6idn.4xlarge",
      var.q_instance_type == "m6idn.8xlarge",
      var.q_instance_type == "m6idn.12xlarge",
      var.q_instance_type == "m6idn.16xlarge",
      var.q_instance_type == "m6idn.24xlarge",
      var.q_instance_type == "m6idn.32xlarge",
      var.q_instance_type == "i4i.xlarge",
      var.q_instance_type == "i4i.2xlarge",
      var.q_instance_type == "i4i.4xlarge",
      var.q_instance_type == "i4i.8xlarge",
      var.q_instance_type == "i4i.12xlarge",
      var.q_instance_type == "i4i.16xlarge",
      var.q_instance_type == "i4i.24xlarge",
      var.q_instance_type == "i4i.32xlarge",
      var.q_instance_type == "i7i.xlarge",
      var.q_instance_type == "i7i.2xlarge",
      var.q_instance_type == "i7i.4xlarge",
      var.q_instance_type == "i7i.8xlarge",
      var.q_instance_type == "i7i.12xlarge",
      var.q_instance_type == "i7i.16xlarge",
      var.q_instance_type == "i7i.24xlarge",     
      var.q_instance_type == "i3en.xlarge",
      var.q_instance_type == "i3en.2xlarge",
      var.q_instance_type == "i3en.3xlarge",
      var.q_instance_type == "i3en.6xlarge",
      var.q_instance_type == "i3en.12xlarge",
      var.q_instance_type == "i3en.24xlarge",
      var.q_instance_type == "i7ie.xlarge",
      var.q_instance_type == "i7ie.2xlarge",
      var.q_instance_type == "i7ie.3xlarge",
      var.q_instance_type == "i7ie.6xlarge",
      var.q_instance_type == "i7ie.12xlarge",
      var.q_instance_type == "i7ie.18xlarge",
      var.q_instance_type == "i7ie.24xlarge",
      var.q_instance_type == "m6i.xlarge",
      var.q_instance_type == "m6i.2xlarge",
      var.q_instance_type == "m6i.4xlarge",
      var.q_instance_type == "m6i.8xlarge",
      var.q_instance_type == "m6i.12xlarge",
      var.q_instance_type == "m6i.16xlarge"
    ])
    error_message = "Only m6i, m6idn, i4i, i7i, i7ie, and i3en instance types are supported.  Must be >=2xlarge. Smaller instance types are only supported with dev_envrionment=true."
  }
}
variable "q_nlb_cross_zone" {
  description = "OPTIONAL: AWS NLB Enable cross-AZ load balancing"
  type        = bool
  default     = false
}
variable "q_nlb_override_subnet_id" {
  description = "OPTIONAL: Private Subnet ID for NLB if deploying in subnet(s) other than subnet(s) the cluster is deployed in"
  type        = string
  default     = null
  validation {
    condition     = var.q_nlb_override_subnet_id == null || can(regex("^subnet-", var.q_nlb_override_subnet_id))
    error_message = "The q_nlb_override_subnet_id must be a valid Subnet ID or list of Subnet IDs of the form 'subnet-', or null if deploying in the same subnet(s) as the cluster."
  }
}
variable "q_nlb_provision" {
  description = "OPTIONAL: Provision an AWS NLB in front of the Qumulo cluster for load balancing and client failover"
  type        = bool
  default     = false
}
variable "q_nlb_internal" {
  description = "OPTIONAL: Makes the NLB for the cluster internal, setting this to false will allow anyone to reach the cluster. Will only work in a dev environment."
  type        = bool
  default     = true
}
variable "q_nlb_stickiness" {
  description = "OPTIONAL: AWS NLB sticky sessions"
  type        = bool
  default     = true
}
variable "q_node_count" {
  description = "Qumulo cluster - node count"
  type        = number
  default     = 3
  validation {
    condition     = var.q_node_count == 1 || (var.q_node_count >= 3 && var.q_node_count <= 24)
    error_message = "The q_node_count value is mandatory.  It is also used to grow a cluster. Specify 3 to 24 nodes or 1 node."
  }
}
variable "q_permissions_boundary" {
  description = "OPTIONAL: Apply an IAM Permissions Boundary Policy to the Qumulo IAM roles that are created for the Qumulo cluster and provisioning instance. This is an account based policy and is optional. Qumulo's IAM roles conform to the least privilege model."
  type        = string
  default     = null
}
variable "q_persistent_storage_type" {
  description = "S3 storage class to persist data in. CNQ Hot uses hot_s3_int(default) or hot_s3_std.  CNQ Cold uses cold_s3_ia or cold_s3_gir.  Be aware that cold options have data retention policies and may incur additional charges, so test with hot classes."
  type        = string
  default     = "hot_s3_int"
  nullable    = false
  validation {
    condition = anytrue([
      var.q_persistent_storage_type == "hot_s3_std",
      var.q_persistent_storage_type == "hot_s3_int",
      var.q_persistent_storage_type == "cold_s3_ia",
      var.q_persistent_storage_type == "cold_s3_gir"
    ])
    error_message = "CNQ Hot uses hot_s3_int or hot_s3_std(default).  CNQ Cold uses cold_s3_ia or cold_s3_gir.  Be aware that cold options have data retention policies and may incur additional charges, so test with hot classes."
  }
}
variable "q_persistent_storage_bucket_policy" {
  description = "An S3 bucket policy will be applied to all S3 buckets if this boolean is set to true.  If you manage bucket policies separate of this deployment then set this to false."
  type        = bool
  default     = true
}
variable "q_replacement_cluster" {
  description = "OPTIONAL: Build a replacement cluster for an existing Terraform deployment.  This requires a new workspace with a separate state file.  This functionality enables in-service changes to the entire compute & cache front-end."
  type        = bool
  default     = false
}
variable "q_target_node_count" {
  description = "Qumulo cluster target node count"
  type        = number
  default     = null
  nullable    = true
  validation {
    condition     = var.q_target_node_count == null || can(var.q_target_node_count == 1 || (var.q_target_node_count >= 3 && var.q_target_node_count <= 23))
    error_message = "The q_target_node_count value is used to shrink the cluster.  Specify 3 to 23 nodes or 1 node. It must be less than q_node_count to take effect."
  }
}
variable "q_write_cache_type" {
  description = "OPTIONAL: Specify the type of EBS boot_dkv"
  type        = string
  default     = "gp3"
  validation {
    condition = anytrue([
      var.q_write_cache_type == "gp2",
      var.q_write_cache_type == "gp3",
      var.q_write_cache_type == "io2"
    ])
    error_message = "An invalid EBS flash type was specified. Must be gp2, gp3, or io2."
  }
}
variable "q_write_cache_tput" {
  description = "OPTIONAL: Specify the throughput, in MB/s, for gp3"
  type        = number
  default     = null
  validation {
    condition     = var.q_write_cache_tput == null || can(var.q_write_cache_tput >= 125 && var.q_write_cache_tput <= 1000)
    error_message = "EBS gp3 throughput must be in the range of 125 to 1000 MB/s."
  }
}
variable "q_write_cache_iops" {
  description = "OPTIONAL: Specify the iops for gp3 or io2.  EBS gp3 IOPS must be in the range of 3000 to 16000. EBS io2 has a max of 256,000 IOPs."
  type        = number
  default     = null
}
variable "s3_bucket_name" {
  description = "AWS S3 bucket name"
  type        = string
  nullable    = false
}
variable "s3_bucket_prefix" {
  description = "AWS S3 bucket prefix (path).  Include a trailing slash (/)"
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^.*/$", var.s3_bucket_prefix))
    error_message = "The s3_bucket_prefix must end with a /"
  }
}
variable "s3_bucket_region" {
  description = "AWS region the S3 bucket is hosted in"
  type        = string
  nullable    = false
}
variable "second_private_subnet_id" {
  description = "A second private subnet ID, in a unique AZ other than the cluster AZ, for single AZ clusters.  This is then used to build a R53 Resolver to forward traffic to Qumulo DNS for Floating IP resolution."
  type        = string
  default     = null
  validation {
    condition     = var.second_private_subnet_id == null || can(regex("^subnet-", var.second_private_subnet_id))
    error_message = "The private_subnet_id must be a valid Subnet ID of the form 'subnet-'."
  }
}
variable "tags" {
  description = "OPTIONAL: Additional global tags"
  type        = map(string)
  default     = null
}
variable "term_protection" {
  description = "Enable Termination Protection"
  type        = bool
  default     = true
}
variable "tf_persistent_storage_workspace" {
  description = "Terraform workspace name for the persistent-storage deployment"
  type        = string
  default     = "default"
  nullable    = false
}
variable "persistent_storage_outputs" {
  type        = any
}