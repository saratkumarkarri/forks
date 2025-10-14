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

output "floating_ips" {
  description = "List of all floating IPs for the Qumulo cluster"
  value       = local.replace_saz_to_saz ? flatten(concat(concat(aws_instance.node[*].secondary_private_ips), local.existing_fips_list)) : flatten(concat(aws_instance.node[*].secondary_private_ips))
}
output "iam_role_arn" {
  description = "IAM role for the cluster"
  value       = aws_iam_role.q_access.arn
}
output "instance_ids" {
  description = "List of all EC2 instance IDs for the Qumulo cluster"
  value       = flatten(concat(aws_instance.node[*].id))
}
output "kms_s3_arn" {
  description = "S3 Key ARN"
  value       = local.kms_s3_arn
}
output "max_floating_ips" {
  description = "Maximum cluster floating IPs"
  value       = local.max_fips
}
output "node1_ip" {
  description = "Primary IP for Node 1"
  value       = aws_instance.node[0].private_ip
}
output "node_names" {
  description = "Name tags for nodes (EC2 Instances)"
  value       = concat(aws_instance.node[*].tags.Name)
}
output "placement_group" {
  description = "Placement group create for the Qumulo cluster"
  value       = aws_placement_group.cluster.name
}
output "persistent_bucket_arns" {
  description = "Persistent S3 storage bucket ARNs"
  value       = flatten(local.persistent_bucket_arns_2)
}
output "persistent_bucket_arns_json" {
  description = "Persistent S3 storage bucket ARNs json encoded"
  value       = local.persistent_bucket_arns_json
}
output "primary_ips" {
  description = "List of all primary IPs for the Qumulo cluster"
  value       = flatten(concat(aws_instance.node[*].private_ip))
}
output "security_group_id" {
  description = "Security group identifier for Qumulo cluster"
  value       = aws_security_group.cluster.id
}
output "temporary_password" {
  description = "Temporary password for Qumulo cluster.  Used prior to forming first quorum."
  value       = tostring(aws_instance.node[0].id)
}
output "url" {
  description = "Link to node 1 in the cluster"
  value       = "https://${tostring(aws_instance.node[0].private_ip)}"
}
output "write_cache_iops" {
  description = "gp3 or io2 Flash IOPS"
  value       = local.write_cache_iops
}
output "write_cache_tput" {
  description = "gp3 Flash throughput"
  value       = local.write_cache_tput
}
output "refill_IOPS" {
  description = "tunable"
  value       = local.refill_IOPS
}
output "refill_Bps" {
  description = "tunable"
  value       = local.refill_Bps
}
output "EBS_BW" {
  description = "tunable"
  value       = local.EBS_BW
}
output "EC2_BW" {
  description = "tunable"
  value       = local.EC2_BW
}
output "disk_count" {
  description = "tunable"
  value       = local.disk_count
}
output "ena_express" {
  description = "yes or no for ENA express support"
  value       = local.ena_express
}
