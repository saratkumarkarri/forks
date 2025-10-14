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
variable "boot_drive_size" {
  description = "Size of the boot drive for each Qumulo Instance"
  type        = number
}
variable "boot_dkv_type" {
  description = "EBS type for boot drive and dkv volumes"
  type        = string
}
variable "cluster_initial_floating_ips" {
  description = "Qumulo floating IP addresses for the cluster"
  type        = number
}
variable "cluster_min_floating_ips_per_node" {
  description = "Qumulo minimum floating IPs per node"
  type        = number
}
variable "cluster_name" {
  description = "Qumulo cluster name"
  type        = string
}
variable "cluster_scripts_path" {
  description = "Local path for Qumulo cluster instance scripts"
  type        = string
}
variable "cluster_sg_cidrs" {
  description = "AWS security group identifiers"
  type        = list(string)
}
variable "cluster_additional_sg_ids" {
  description = "AWS additional security group Ids"
  type        = list(string)
}
variable "cluster_persistent_storage_capacity_limit" {
  description = "Soft capacity limit for all buckets combined."
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
  description = "The deployment_unique_name of the previous deployed cluster you want to replace"
  type        = string
}
variable "install_s3_prefix" {
  description = "S3 prefix for Qumulo core installer and package"
  type        = string
}
variable "instance_recovery_topic" {
  description = "AWS SNS topic for Qumulo instance recovery"
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
variable "nlb_provision" {
  description = "Provision an AWS NLB in front of the Qumulo cluster for load balancing and client failover"
  type        = bool
}
variable "node_count" {
  description = "Qumulo cluster node count"
  type        = number
}
variable "permissions_boundary" {
  description = "OPTIONAL: Apply an IAM Permissions Boundary Policy to the Qumulo IAM roles that are created for the Qumulo cluste. This is an account based policy and is optional. Qumulo's IAM roles conform to the least privilege model."
  type        = string
}
variable "persistent_bucket_arns" {
  description = "Persistent cluster storage bucket ARNs."
  type        = string
}
variable "private_subnet_ids" {
  description = "AWS private subnet identifiers"
  type        = list(string)
}
variable "replacement_cluster" {
  description = "Build a replacement cluster for an existing Terraform deployment."
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
variable "write_cache_type" {
  description = "OPTIONAL: Specify the type of EBS flash"
  type        = string
}
variable "write_cache_tput" {
  description = "OPTIONAL: Specify the throughput, in MB/s, for gp3"
  type        = number
}
variable "write_cache_iops" {
  description = "OPTIONAL: Specify the iops for gp3 or io2"
  type        = number
}
variable "ec2_map" {
  description = "This map is used to to set tunables based on the EC2 instance type"
  type = map(object({
    wcacheSlots : number
    wcacheSize : number
    wcacheIOPSgp3 : number
    wcacheIOPSio2 : number
    wcacheTput : number
    wcacheRefillIOPs : number
    wcacheRefillBps : number
    wcacheEBSBW : number
    wcacheEC2BW : number
    dkvSlots : number
    dkvSize : number
    rcacheSlots : number
    nodeCap : number
    enaExpress : string
    maxSecIPs : number
  }))
  default = {
    "m6idn.xlarge" = {
      wcacheSlots      = 6
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 351
      wcacheEC2BW      = 703
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 100
      enaExpress       = "no"
      maxSecIPs        = 14
    }
    "m6idn.2xlarge" = {
      wcacheSlots      = 10
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 703
      wcacheEC2BW      = 1406
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 196
      enaExpress       = "no"
      maxSecIPs        = 14
    }
    "m6idn.4xlarge" = {
      wcacheSlots      = 18
      wcacheSize       = 16
      wcacheIOPSgp3    = 3472
      wcacheIOPSio2    = 579
      wcacheTput       = 145
      wcacheRefillIOPs = 3472
      wcacheRefillBps  = 145
      wcacheEBSBW      = 1406
      wcacheEC2BW      = 2813
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 502
      enaExpress       = "no"
      maxSecIPs        = 29
    }
    "m6idn.8xlarge" = {
      wcacheSlots      = 18
      wcacheSize       = 16
      wcacheIOPSgp3    = 6944
      wcacheIOPSio2    = 1157
      wcacheTput       = 289
      wcacheRefillIOPs = 6944
      wcacheRefillBps  = 289
      wcacheEBSBW      = 2813
      wcacheEC2BW      = 5625
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 1488
      enaExpress       = "no"
      maxSecIPs        = 29
    }
    "m6idn.12xlarge" = {
      wcacheSlots      = 18
      wcacheSize       = 24
      wcacheIOPSgp3    = 10417
      wcacheIOPSio2    = 1737
      wcacheTput       = 434
      wcacheRefillIOPs = 10417
      wcacheRefillBps  = 434
      wcacheEBSBW      = 4219
      wcacheEC2BW      = 8438
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 2232
      enaExpress       = "no"
      maxSecIPs        = 29
    }
    "m6idn.16xlarge" = {
      wcacheSlots      = 18
      wcacheSize       = 32
      wcacheIOPSgp3    = 13889
      wcacheIOPSio2    = 2315
      wcacheTput       = 579
      wcacheRefillIOPs = 13889
      wcacheRefillBps  = 579
      wcacheEBSBW      = 5625
      wcacheEC2BW      = 11250
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 2976
      enaExpress       = "no"
      maxSecIPs        = 49
    }
    "m6idn.24xlarge" = {
      wcacheSlots      = 18
      wcacheSize       = 32
      wcacheIOPSgp3    = 16000
      wcacheIOPSio2    = 2667
      wcacheTput       = 868
      wcacheRefillIOPs = 16000
      wcacheRefillBps  = 868
      wcacheEBSBW      = 8438
      wcacheEC2BW      = 16875
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 4464
      enaExpress       = "no"
      maxSecIPs        = 49
    }
    "m6idn.32xlarge" = {
      wcacheSlots      = 18
      wcacheSize       = 32
      wcacheIOPSgp3    = 16000
      wcacheIOPSio2    = 2667
      wcacheTput       = 1000
      wcacheRefillIOPs = 16000
      wcacheRefillBps  = 1000
      wcacheEBSBW      = 11250
      wcacheEC2BW      = 22500
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 5952
      enaExpress       = "no"
      maxSecIPs        = 49
    }
    "i4i.xlarge" = {
      wcacheSlots      = 3
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 141
      wcacheEC2BW      = 211
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 196
      enaExpress       = "no"
      maxSecIPs        = 14
    }
    "i4i.2xlarge" = {
      wcacheSlots      = 4
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 281
      wcacheEC2BW      = 527
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 502
      enaExpress       = "no"
      maxSecIPs        = 14
    }
    "i4i.4xlarge" = {
      wcacheSlots      = 8
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 563
      wcacheEC2BW      = 1055
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 1488
      enaExpress       = "no"
      maxSecIPs        = 29
    }
    "i4i.8xlarge" = {
      wcacheSlots      = 16
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 1125
      wcacheEC2BW      = 2109
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 2976
      enaExpress       = "yes"
      maxSecIPs        = 29
    }
    "i4i.12xlarge" = {
      wcacheSlots      = 18
      wcacheSize       = 16
      wcacheIOPSgp3    = 4167
      wcacheIOPSio2    = 667
      wcacheTput       = 174
      wcacheRefillIOPs = 4167
      wcacheRefillBps  = 174
      wcacheEBSBW      = 1688
      wcacheEC2BW      = 3164
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 4464
      enaExpress       = "yes"
      maxSecIPs        = 29
    }
    "i4i.16xlarge" = {
      wcacheSlots      = 18
      wcacheSize       = 16
      wcacheIOPSgp3    = 5556
      wcacheIOPSio2    = 889
      wcacheTput       = 231
      wcacheRefillIOPs = 5556
      wcacheRefillBps  = 231
      wcacheEBSBW      = 2250
      wcacheEC2BW      = 4219
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 5952
      enaExpress       = "yes"
      maxSecIPs        = 49
    }
    "i4i.24xlarge" = {
      wcacheSlots      = 16
      wcacheSize       = 24
      wcacheIOPSgp3    = 9375
      wcacheIOPSio2    = 1500
      wcacheTput       = 391
      wcacheRefillIOPs = 9375
      wcacheRefillBps  = 391
      wcacheEBSBW      = 3375
      wcacheEC2BW      = 6328
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 8928
      enaExpress       = "yes"
      maxSecIPs        = 29
    }
    "i4i.32xlarge" = {
      wcacheSlots      = 14
      wcacheSize       = 32
      wcacheIOPSgp3    = 14286
      wcacheIOPSio2    = 2286
      wcacheTput       = 596
      wcacheRefillIOPs = 14286
      wcacheRefillBps  = 596
      wcacheEBSBW      = 4500
      wcacheEC2BW      = 8438
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 11904
      enaExpress       = "yes"
      maxSecIPs        = 49
    }
    "i3en.xlarge" = {
      wcacheSlots      = 3
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 130
      wcacheEC2BW      = 473
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 196
      enaExpress       = "no"
      maxSecIPs        = 14
    }
    "i3en.2xlarge" = {
      wcacheSlots      = 4
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 260
      wcacheEC2BW      = 945
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 502
      enaExpress       = "no"
      maxSecIPs        = 14
    }
    "i3en.3xlarge" = {
      wcacheSlots      = 6
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 428
      wcacheEC2BW      = 1406
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 753
      enaExpress       = "no"
      maxSecIPs        = 14
    }
    "i3en.6xlarge" = {
      wcacheSlots      = 8
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 534
      wcacheEC2BW      = 2813
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 2232
      enaExpress       = "no"
      maxSecIPs        = 29
    }
    "i3en.12xlarge" = {
      wcacheSlots      = 16
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 1069
      wcacheEC2BW      = 5625
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 4464
      enaExpress       = "no"
      maxSecIPs        = 29
    }
    "i3en.24xlarge" = {
      wcacheSlots      = 18
      wcacheSize       = 16
      wcacheIOPSgp3    = 5728
      wcacheIOPSio2    = 955
      wcacheTput       = 220
      wcacheRefillIOPs = 5728
      wcacheRefillBps  = 220
      wcacheEBSBW      = 2138
      wcacheEC2BW      = 11250
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 8928
      enaExpress       = "no"
      maxSecIPs        = 49
    }
    "i7ie.xlarge" = {
      wcacheSlots      = 3
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 141
      wcacheEC2BW      = 469
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 196
      enaExpress       = "no"
      maxSecIPs        = 14
    }
    "i7ie.2xlarge" = {
      wcacheSlots      = 4
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 281
      wcacheEC2BW      = 915
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 502
      enaExpress       = "no"
      maxSecIPs        = 14
    }
    "i7ie.3xlarge" = {
      wcacheSlots      = 6
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 422
      wcacheEC2BW      = 1406
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 753
      enaExpress       = "no"
      maxSecIPs        = 14
    }
    "i7ie.6xlarge" = {
      wcacheSlots      = 12
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 844
      wcacheEC2BW      = 1406
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 2232
      enaExpress       = "no"
      maxSecIPs        = 29
    }
    "i7ie.12xlarge" = {
      wcacheSlots      = 24
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 1688
      wcacheEC2BW      = 2813
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 4464
      enaExpress       = "yes"
      maxSecIPs        = 49
    }
    "i7ie.18xlarge" = {
      wcacheSlots      = 36
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 2531
      wcacheEC2BW      = 4219
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 6696
      enaExpress       = "yes"
      maxSecIPs        = 49
    }
    "i7ie.24xlarge" = {
      wcacheSlots      = 48
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 3375
      wcacheEC2BW      = 5625
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 8928
      enaExpress       = "yes"
      maxSecIPs        = 49
    }
    "i7ie.48xlarge" = {
      wcacheSlots      = 96
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 6750
      wcacheEC2BW      = 11250
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 17856
      enaExpress       = "yes"
      maxSecIPs        = 49
    }
    "m6i.xlarge" = {
      wcacheSlots      = 3
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 141
      wcacheEC2BW      = 176
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 1
      nodeCap          = 100
      enaExpress       = "no"
      maxSecIPs        = 14
    }
    "m6i.2xlarge" = {
      wcacheSlots      = 5
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 281
      wcacheEC2BW      = 352
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 1
      nodeCap          = 196
      enaExpress       = "no"
      maxSecIPs        = 14
    }
    "m6i.4xlarge" = {
      wcacheSlots      = 9
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 563
      wcacheEC2BW      = 703
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 2
      nodeCap          = 502
      enaExpress       = "no"
      maxSecIPs        = 29
    }
    "m6i.8xlarge" = {
      wcacheSlots      = 14
      wcacheSize       = 16
      wcacheIOPSgp3    = 3571
      wcacheIOPSio2    = 596
      wcacheTput       = 149
      wcacheRefillIOPs = 3571
      wcacheRefillBps  = 149
      wcacheEBSBW      = 1125
      wcacheEC2BW      = 1406
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 4
      nodeCap          = 1488
      enaExpress       = "no"
      maxSecIPs        = 29
    }
    "m6i.12xlarge" = {
      wcacheSlots      = 12
      wcacheSize       = 24
      wcacheIOPSgp3    = 6250
      wcacheIOPSio2    = 1042
      wcacheTput       = 260
      wcacheRefillIOPs = 6250
      wcacheRefillBps  = 260
      wcacheEBSBW      = 1688
      wcacheEC2BW      = 2109
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 6
      nodeCap          = 2232
      enaExpress       = "no"
      maxSecIPs        = 29
    }
    "m6i.16xlarge" = {
      wcacheSlots      = 10
      wcacheSize       = 32
      wcacheIOPSgp3    = 10000
      wcacheIOPSio2    = 1667
      wcacheTput       = 417
      wcacheRefillIOPs = 10000
      wcacheRefillBps  = 417
      wcacheEBSBW      = 2250
      wcacheEC2BW      = 2813
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 8
      nodeCap          = 2976
      enaExpress       = "no"
      maxSecIPs        = 49
    }
    "i7i.xlarge" = {
      wcacheSlots      = 3
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 141
      wcacheEC2BW      = 211
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 196
      enaExpress       = "no"
      maxSecIPs        = 14
    }
    "i7i.2xlarge" = {
      wcacheSlots      = 4
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 281
      wcacheEC2BW      = 527
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 502
      enaExpress       = "no"
      maxSecIPs        = 14
    }
    "i7i.4xlarge" = {
      wcacheSlots      = 8
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 563
      wcacheEC2BW      = 1055
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 1488
      enaExpress       = "no"
      maxSecIPs        = 29
    }
    "i7i.8xlarge" = {
      wcacheSlots      = 16
      wcacheSize       = 16
      wcacheIOPSgp3    = 3000
      wcacheIOPSio2    = 500
      wcacheTput       = 125
      wcacheRefillIOPs = 0
      wcacheRefillBps  = 0
      wcacheEBSBW      = 1125
      wcacheEC2BW      = 2109
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 2976
      enaExpress       = "no"
      maxSecIPs        = 29
    }
    "i7i.12xlarge" = {
      wcacheSlots      = 18
      wcacheSize       = 16
      wcacheIOPSgp3    = 4167
      wcacheIOPSio2    = 667
      wcacheTput       = 174
      wcacheRefillIOPs = 4167
      wcacheRefillBps  = 174
      wcacheEBSBW      = 1688
      wcacheEC2BW      = 3164
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 4464
      enaExpress       = "yes"
      maxSecIPs        = 29
    }
    "i7i.16xlarge" = {
      wcacheSlots      = 18
      wcacheSize       = 16
      wcacheIOPSgp3    = 5556
      wcacheIOPSio2    = 889
      wcacheTput       = 231
      wcacheRefillIOPs = 5556
      wcacheRefillBps  = 231
      wcacheEBSBW      = 2250
      wcacheEC2BW      = 4219
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 5952
      enaExpress       = "yes"
      maxSecIPs        = 49
    }
    "i7i.24xlarge" = {
      wcacheSlots      = 16
      wcacheSize       = 24
      wcacheIOPSgp3    = 9375
      wcacheIOPSio2    = 1500
      wcacheTput       = 391
      wcacheRefillIOPs = 9375
      wcacheRefillBps  = 391
      wcacheEBSBW      = 3375
      wcacheEC2BW      = 6328
      dkvSlots         = 4
      dkvSize          = 4
      rcacheSlots      = 0
      nodeCap          = 8928
      enaExpress       = "yes"
      maxSecIPs        = 49
    }    
  }
}