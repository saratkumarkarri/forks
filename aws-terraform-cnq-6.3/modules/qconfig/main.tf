#MIT License

#Copyright (c) 2024 Qumulo, Inc.

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

data "aws_subnet" "private_subnet_ids_map" {
  for_each = toset(var.private_subnet_ids)

  id = each.key
}
data "aws_subnet" "nlb_subnet_ids_map" {
  for_each = toset(var.nlb_subnet_ids)

  id = each.key
}

locals {
  #Validate the persistent storage is in the same region as the cluster
  valid_qps_region = var.aws_region == var.persistent_storage_bucket_region

  #Find the number of AZs desired
  number_azs     = length(var.private_subnet_ids)
  number_nlb_azs = length(var.nlb_subnet_ids)
  maz            = local.number_azs > 1
  saz            = !local.maz

  #Multi-AZ validation
  valid_4_maz_region = local.saz || local.number_azs == 3 || (local.number_azs == 4 && (var.aws_region == "us-west-2" || var.aws_region == "us-east-1" || var.aws_region == "ap-northeast-2"))

  valid_number_azs     = local.number_azs == 1 || local.number_azs >= 3
  valid_number_nlb_azs = local.number_nlb_azs == local.number_azs

  valid_maz_majority_quorum        = local.number_azs == 1 || (local.number_azs == 3 && (var.node_count == 3 || var.node_count > 4)) || local.number_azs > 3
  valid_maz_majority_quorum_target = var.target_node_count == null || var.replacement_cluster ? true : (var.target_node_count < var.node_count && local.number_azs == 3 ? var.target_node_count == 3 || var.target_node_count > 4 : true)

  #Calculate max nodes per AZ for MAZ deployment
  nodes_per_az = ceil(var.node_count / local.number_azs)

  #swap the key to the AZ name and the map will sort based on the AZ name
  private_azs_map = {
    for v in data.aws_subnet.private_subnet_ids_map : v.availability_zone => v.id...
  }
  nlb_azs_map = {
    for v in data.aws_subnet.nlb_subnet_ids_map : v.availability_zone => v.id...
  }

  #get the private AZ IDs to check for us-east-1 invalid AZ
  private_az_ids = [
    for v in data.aws_subnet.private_subnet_ids_map : v.availability_zone_id
  ]
  nlb_az_ids = [
    for v in data.aws_subnet.nlb_subnet_ids_map : v.availability_zone_id
  ]
  invalid_us_east_az_ids = contains(local.private_az_ids, "use1-az3") || contains(local.nlb_az_ids, "use1-az3")

  #get the subnet IDs
  private_subnet_id_per_az = [
    for v in local.private_azs_map : v[0]
  ]
  nlb_subnet_id_per_az = [
    for v in local.nlb_azs_map : v[0]
  ]

  #create the fault domains per AZ
  private_fault_domain_id_per_az = local.maz ? range(1, local.number_azs + 1) : [for i in range(var.node_count) : "none"]

  #build the full list of subnet IDs and fault domains for every node, keeping order
  private_subnet_id_per_node_full = local.maz ? flatten([
    for i in range(local.nodes_per_az) : local.private_subnet_id_per_az]) : flatten([
  for i in range(var.node_count) : local.private_subnet_id_per_az])

  private_fault_domain_id_per_node_full = flatten([
  for i in range(local.nodes_per_az) : local.private_fault_domain_id_per_az])

  private_subnet_id_per_node = slice(local.private_subnet_id_per_node_full, 0, var.node_count)

  private_fault_domain_id_per_node = slice(local.private_fault_domain_id_per_node_full, 0, var.node_count)

  #get the AZs
  private_azs = [
    for k, v in local.private_azs_map : k
  ]
  nlb_azs = [
    for k, v in local.nlb_azs_map : k
  ]
  unique_azs     = length(local.private_azs) == local.number_azs
  unique_nlb_azs = length(local.nlb_azs) == local.number_nlb_azs

}

#Error checking null-resources
resource "null_resource" "check_valid_bucket_region" {
  count = local.valid_qps_region ? 0 : "S3 buckets are deployed in a different region from the cluster.  Align the regions!"
}
resource "null_resource" "check_valid_number_azs" {
  count = local.valid_number_azs ? 0 : "Invalid number of private subnet IDs.  Specify 1 private subnet ID for a single AZ deployment.  Specify >=3 private subnet IDs for a multi-AZ deployment."
}
resource "null_resource" "check_valid_number_nlb_azs" {
  count = local.valid_number_nlb_azs ? 0 : "var.q_nlb_override_subnet_id is not null and the number of subnet IDs for the NLB doesn't match the number of private subnet IDs for the cluster."
}
resource "null_resource" "check_valid_4_maz_region" {
  count = local.valid_4_maz_region ? 0 : "Invalid four zone multi-AZ region. 4 AZ regions: us-west-2, us-east-1, or ap-northeast-2."
}
resource "null_resource" "check_unique_azs" {
  count = local.unique_azs ? 0 : "Two or more of the private subnet IDs provided are in the same AZ."
}
resource "null_resource" "check_unique_nlb_azs" {
  count = local.unique_nlb_azs ? 0 : "Two or more of the q_nlb_override_subnet_ids provided are in the same AZ."
}
resource "null_resource" "check_invalid_us_east_az_ids" {
  count = !local.invalid_us_east_az_ids ? 0 : "AWS us-east-1 AZ ID = use1-az3 does not support Qumulo required EC2 instance types. Either or both q_private_subnet_id and q_nlb_overried_private_subnet_id have an invalid subnet ID."
}
resource "null_resource" "check_valid_maz_majority_quorum" {
  count = local.valid_maz_majority_quorum ? 0 : "q_node_count = 4 is not a valid cluster size for a multi-AZ deployment with 3 AZs.  Either use 3 nodes or 5 or more."
}
resource "null_resource" "check_valid_maz_majority_quorum_target" {
  count = local.valid_maz_majority_quorum_target ? 0 : "q_target_node_count = 4 (or < 3) is not a valid cluster size for a multi-AZ deployment with 3 AZs.  Either use 3 nodes or 5 or more."
}