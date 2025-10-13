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

# **** Version 1.6 ****

locals {
  #Calculate the number of buckets to create
  number_buckets_calc = ceil(var.soft_capacity_limit / 500)
  number_buckets      = local.number_buckets_calc < 16 ? 16 : local.number_buckets_calc
  soft_capacity_bytes = tostring(var.soft_capacity_limit * 1000 * 1000 * 1000 * 1000)

  #local variable for cleaner references in subsequent use
  deployment_unique_name = null_resource.name_lock.triggers.deployment_unique_name

  #AWS providers before 5.0 do not support calling the resource with '.bucket_regional_domain_name' and returning the URI with the region
  #To avoid this we build the URIs here to support pre-v5 AWS providers.  Even though we technically require >=5.0 AWS provider.
  generate_uris = [
    for i in range(length(aws_s3_bucket.cnq_bucket)) : {
      uri = "${aws_s3_bucket.cnq_bucket[i].bucket}.s3.${var.aws_region}.amazonaws.com"
    }
  ]
}

#Generates 11 digit random alphanumeric for the deployment_unique_name.  Generated on first apply and never changes.
resource "random_string" "deployment" {
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

#This  resource is used to 'lock' the deployment_unique_name.  Any changes to the deployment_name after the first apply are ignored.
#Appends the random alpha numeric to the deployment name.  All resources are tagged/named with this unique name.
resource "null_resource" "name_lock" {
  triggers = {
    deployment_unique_name = "${var.deployment_name}-${random_string.deployment.id}"
  }

  lifecycle { ignore_changes = all }
}

#Generates 11 digit random alphanumeric for the deployment_unique_name.  Generated on first apply and never changes.
resource "random_string" "bucket" {
  count = local.number_buckets

  length      = 11
  lower       = true
  min_lower   = 8
  min_numeric = 1
  numeric     = true
  special     = false
  upper       = false
  keepers = {
    name = local.deployment_unique_name
  }
  lifecycle { ignore_changes = all }
}

#Create the buckets
resource "aws_s3_bucket" "cnq_bucket" {
  count = local.number_buckets

  bucket        = lower("${random_string.bucket[count.index].id}-${local.deployment_unique_name}-qps-${count.index + 1}")
  force_destroy = !var.prevent_destroy

  tags = merge(var.tags, { Name = "${random_string.bucket[count.index].id}-${local.deployment_unique_name}-qps-${count.index + 1}" })

  lifecycle {
    ignore_changes = [
      # Ignore all properties except `force_destroy`
      bucket,
      bucket_prefix,
      object_lock_enabled,
      tags
    ]
  }
}

resource "aws_s3_bucket_logging" "cnq_bucket" {
  count = var.s3_log_bucket_name == null ? 0 : local.number_buckets

  bucket        = aws_s3_bucket.cnq_bucket[count.index].id
  target_bucket = var.s3_log_bucket_name
  target_prefix = var.s3_log_bucket_prefix
}

#Put the bucket ARNs, URIs, region, and cluster capacity in parameter store
resource "aws_ssm_parameter" "bucket-arns" {
  name  = "/qumulo/${local.deployment_unique_name}/bucket-arns"
  type  = "SecureString"
  value = join(", ", flatten(concat(aws_s3_bucket.cnq_bucket[*].arn)))
}
resource "aws_ssm_parameter" "bucket-names" {
  name  = "/qumulo/${local.deployment_unique_name}/bucket-names"
  type  = "SecureString"
  value = join(", ", flatten(concat(aws_s3_bucket.cnq_bucket[*].bucket)))
}
resource "aws_ssm_parameter" "bucket-region" {
  name  = "/qumulo/${local.deployment_unique_name}/bucket-region"
  type  = "SecureString"
  value = var.aws_region
}
resource "aws_ssm_parameter" "bucket-uris" {
  name  = "/qumulo/${local.deployment_unique_name}/bucket-uris"
  type  = "SecureString"
  value = join(",", flatten(concat(local.generate_uris[*].uri)))
}
resource "aws_ssm_parameter" "soft-capacity-limit" {
  name  = "/qumulo/${local.deployment_unique_name}/soft-capacity-limit"
  type  = "SecureString"
  value = local.soft_capacity_bytes
}
