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

variable "ami_id" {
  description = "Qumulo AMI-ID"
  type        = string
  validation {
    condition     = var.ami_id == null || can(regex("^ami-[0-9A-Za-z]{17}$", var.ami_id))
    error_message = "The ami_id is invalid."
  }
}
variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}
variable "aws_number_azs" {
  description = "AWS Number of AZs"
  type        = number
}
variable "aws_partition" {
  description = "AWS partition"
  type        = string
}
variable "aws_region" {
  description = "AWS region"
  type        = string
}
variable "aws_vpc_id" {
  description = "AWS VPC identifier"
  type        = string
}
variable "boot_type" {
  description = "OPTIONAL: Specify the type of EBS for the boot drive"
  type        = string
}
variable "boot_volume_size" {
  description = "Size (GB) of the provisioner root EBS volume. Must be large enough for the AMI snapshot."
  type        = number
  default     = 150
  validation {
    condition     = var.boot_volume_size >= 150
    error_message = "The provisioner root volume must be at least 150 GB to satisfy the AMI snapshot requirements."
  }
}
variable "check_provisioner_shutdown" {
  description = "Executes a local-exec script on the Terraform machine to check if the provisioner instance shutdown which indicates a successful cluster deployment."
  type        = bool
}
variable "cluster_additional_sg_ids" {
  description = "AWS additional security group Ids"
  type        = list(string)
}
variable "cluster_fault_domain_ids" {
  description = "List of fault domain IDs for the nodes in the cluster for the Qumulo cluster"
  type        = list(string)
}
variable "cluster_floating_ips" {
  description = "List of all floating IPs for the Qumulo cluster"
  type        = list(string)
}
variable "cluster_fqdn" {
  description = "Fully qualified domain name for Qumulo DNS"
  type        = string
}
variable "cluster_iam_role_arn" {
  description = "IAM role for the cluster"
  type        = string
}
variable "cluster_instance_ids" {
  description = "List of all EC2 instance IDs for the Qumulo cluster"
  type        = list(string)
}
variable "cluster_max_floating_ips" {
  description = "Maximum floating ips for the cluster"
  type        = number
}
variable "cluster_name" {
  description = "Qumulo cluster name"
  type        = string
}
variable "cluster_node1_ip" {
  description = "Primary IP for Node 1"
  type        = string
}
variable "cluster_persistent_bucket_uris" {
  description = "Qumulo S3 persistent storage bucket URIs"
  type        = string
}
variable "cluster_persistent_bucket_arns_json" {
  description = "Qumulo S3 persistent storage bucket ARNs json encoded"
  type        = string
}
variable "cluster_persistent_bucket_arns" {
  description = "Qumulo S3 persistent storage bucket ARNs"
  type        = list(string)
}
variable "cluster_persistent_bucket_policy" {
  description = "An S3 bucket policy will be applied to all S3 buckets if this boolean is set to true.  If you manage bucket policies separate of this deployment then set this to false."
  type        = bool
}
variable "cluster_persistent_bucket_names" {
  description = "Qumulo S3 persistent storage bucket names"
  type        = string
}
variable "cluster_persistent_storage_type" {
  description = "S3 storage class to persist data in. CNQ Hot uses hot_s3_int or hot_s3_std(default).  CNQ Cold uses cold_s3_ia or cold_s3_gir.  Be aware that cold options have data retention policies and may incur additional charges, so test with hot classes."
  type        = string
}
variable "cluster_persistent_storage_capacity_limit" {
  description = "Soft capacity limit for all buckets combined."
  type        = string
}
variable "cluster_primary_ips" {
  description = "List of all primary IPs for the Qumulo cluster"
  type        = list(string)
}
variable "cluster_secrets_arn" {
  description = "Cluster secrets ARN"
  type        = string
}
variable "cluster_sg_cidrs" {
  description = "AWS security group identifiers"
  type        = list(string)
}
variable "cluster_sg_id" {
  description = "Cluster security group id"
  type        = string
}
variable "cluster_temporary_password" {
  description = "Temporary password for Qumulo cluster.  Used prior to forming first quorum."
  type        = string
}
variable "cluster_version" {
  description = "Qumulo cluster software version"
  type        = string
}
variable "debian_package" {
  description = "Debian or RHL package"
  type        = bool
}
variable "deployment_unique_name" {
  description = "Unique Name for this Terraform deployment.  This is the deployment name plus 12 random hex digits that will be used for all resource names where appropriate."
  type        = string
}
variable "ec2_key_pair" {
  description = "AWS EC2 key pair"
  type        = string
}
variable "existing_deployment_unique_name" {
  description = "OPTIONAL: The deployment_unique_name of the previous deployed cluster you want to replace"
  type        = string
}
variable "ena_express" {
  description = "yes or no for ENA Express support for the instance type"
  type        = string
}
variable "flash_tput" {
  description = "OPTIONAL: Specify the throughput, in MB/s, for gp3"
  type        = number
}
variable "flash_iops" {
  description = "OPTIONAL: Specify the iops for gp3 or io2"
  type        = number
}
variable "functions_s3_prefix" {
  description = "AWS S3 prefix for provisioner functions"
  type        = string
}
variable "install_s3_prefix" {
  description = "AWS S3 prefix for Qumulo Core package location"
  type        = string
}
variable "instance_type" {
  description = "Qumulo EC2 instance type"
  type        = string
}
variable "kms_key_id" {
  description = "AWS KMS encryption key identifier"
  type        = string
}
variable "kms_s3_arn" {
  description = "S3 Key ARN"
  type        = string
}
variable "permissions_boundary" {
  description = "OPTIONAL: Apply an IAM Permissions Boundary Policy to the Qumulo IAM roles that are created for the provisioning instance. This is an account based policy and is optional. Qumulo's IAM roles conform to the least privilege model."
  type        = string
}
variable "private_subnet_id" {
  description = "AWS private subnet identifier"
  type        = string
}
variable "replacement_cluster" {
  description = "OPTIONAL: Build a replacement cluster for an existing Terraform deployment.  This requires a new workspace with a separate state file.  This functionality enables in-service changes to the entire compute & cache front-end."
  type        = bool
}
variable "require_imdsv2" {
  description = "Force all Instance Metadata Service Requests to us v2 Tokens"
  type        = bool
}
variable "s3_bucket_name" {
  description = "AWS S3 bucket name"
  type        = string
}
variable "s3_bucket_region" {
  description = "AWS region the S3 bucket is hosted in"
  type        = string
}
variable "scripts_path" {
  description = "Local path for provisioner scripts"
  type        = string
}
variable "scripts_s3_prefix" {
  description = "AWS S3 prefix for provisioner scripts"
  type        = string
}
variable "tags" {
  description = "Additional global tags"
  type        = map(string)
}
variable "target_node_count" {
  description = "The desired node count in the cluster.  Used for removing nodes and shrinking the cluster."
  type        = number
}
variable "term_protection" {
  description = "Enable Termination Protection"
  type        = bool
}
variable "tun_refill_IOPS" {
  description = "Tunable"
  type        = string
}
variable "tun_refill_Bps" {
  description = "Tunable"
  type        = string
}
variable "tun_EBS_BW" {
  description = "Tunable"
  type        = string
}
variable "tun_EC2_BW" {
  description = "Tunable"
  type        = string
}
variable "tun_disk_count" {
  description = "Tunable"
  type        = string
}