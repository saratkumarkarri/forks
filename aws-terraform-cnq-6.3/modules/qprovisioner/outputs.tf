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

locals {
  final_node_count    = var.check_provisioner_shutdown ? length(tolist(split(",", nonsensitive(data.aws_ssm_parameter.node-ips[0].value)))) : 0
  deployed_node_count = length(var.cluster_primary_ips)
  cleanup             = var.check_provisioner_shutdown ? local.final_node_count < local.deployed_node_count : false
  cleanup_nodes       = local.cleanup ? join(", ", slice(var.cluster_primary_ips, local.final_node_count, local.deployed_node_count)) : null
}

output "cleanup" {
  description = "If nodes were removed from the cluster and now need to be subsequently destroyed"
  value       = local.cleanup
}

output "cleanup_nodes" {
  description = "List of nodes were removed from the cluster and now need to be subsequently destroyed"
  value       = local.cleanup_nodes
}

output "floating_ips" {
  description = "Floating IPs for the Qumulo Cluster"
  value       = var.check_provisioner_shutdown ? tolist(split(",", nonsensitive(data.aws_ssm_parameter.floating-ips[0].value))) : ["Check Parameter Store https://qumulo/${var.deployment_unique_name}/float-ips"]
}

output "primary_ips" {
  description = "Primary IPs for the Qumulo Cluster"
  value       = var.check_provisioner_shutdown ? tolist(split(",", nonsensitive(data.aws_ssm_parameter.node-ips[0].value))) : ["Check Parameter Store https://qumulo/${var.deployment_unique_name}/node-ips"]
}

output "status" {
  description = "If the provisioner instance completed secondary provisioning of the cluster = Success/Failure"
  value       = var.check_provisioner_shutdown ? nonsensitive(data.aws_ssm_parameter.qprovisioner[0].value) == "Shutting down provisioning instance" ? "Success" : "FAILURE" : "Validate secondary provisioning of the cluster completed.  Verify EC2 Instance ID ${aws_instance.provisioner.id} auto shutdown or check Parameter Store ${aws_ssm_parameter.last-run-status.arn}"
}
