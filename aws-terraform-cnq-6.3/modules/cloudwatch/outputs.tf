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

output "cluster_rg_write_cache" {
  description = "Name of the Qumulo Cluster Resource Group - Write Cache"
  value       = aws_resourcegroups_group.cluster_rg_tw.name
}
output "cluster_rg_dkv" {
  description = "Name of the Qumulo Cluster Resource Group - DKV"
  value       = aws_resourcegroups_group.cluster_rg_dkv.name
}
output "cluster_rg_s3" {
  description = "Name of the Qumulo Cluster Resource Group - Persistent Object Storage"
  value       = aws_resourcegroups_group.cluster_rg_s3.name
}
/*
output "cluster_cloudwatch_dashboard" {
  description = "Name of the Qumulo Cluster Cloudwatch Dashboard"
  value       = aws_cloudwatch_dashboard.cw_dashboard.dashboard_name
}
*/
output "cluster_audit_log" {
  description = "Name of the Cloudwatch LogGroup created to store Cluster's Audit Log"
  value       = var.audit_logging ? aws_cloudwatch_log_group.audit_log[0].name : null
}