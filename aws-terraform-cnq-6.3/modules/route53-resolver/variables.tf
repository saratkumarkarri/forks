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

variable "aws_vpc_id" {
  description = "AWS VPC ID"
  type        = string
}
variable "aws_vpc_cidr" {
  description = "AWS VPC CIDR"
  type        = string
}
variable "deployment_unique_name" {
  description = "Unique Name for this Terraform deployment.  This is the deployment name plus 12 random hex digits that will be used for all resource names where appropriate."
  type        = string
}
variable "fqdn" {
  description = "The Fully Qualified Domain Name (FQDN) for Qumulo DNS "
  type        = string
}
variable "private_subnet_id" {
  description = "AWS private subnet identifier"
  type        = string
}
variable "second_private_subnet_id" {
  description = "A second private subnet ID, in a unique AZ other than the cluster AZ, for single AZ clusters.  This is then used to build a R53 Resolver to forward traffic to Qumulo DNS for Floating IP resolution."
  type        = string
}
variable "target_ips" {
  description = "A list of floating IPs for the cluster that the R53 resolver will forward DNS queries too."
  type        = list(string)
}
variable "tags" {
  description = "Additional global tags"
  type        = map(string)
}
