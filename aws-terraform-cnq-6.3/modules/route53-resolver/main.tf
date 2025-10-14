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

# Lookup subnet 1
data "aws_subnet" "subnet1" {
  id = var.private_subnet_id
}

# Lookup subnet 2
data "aws_subnet" "subnet2" {
  id = var.second_private_subnet_id
}

locals {
  az1        = data.aws_subnet.subnet1.availability_zone
  az2        = data.aws_subnet.subnet2.availability_zone
  unique_azs = local.az1 != local.az2

  resolver_subnets = [var.private_subnet_id, var.second_private_subnet_id]
}

resource "null_resource" "check_unique_azs" {
  count = local.unique_azs ? 0 : "The private subnet IDs provided for the R53 Resolver are in the same AZ. Correct second_private_subnet_id."
}

resource "aws_security_group" "r53_resolver_sg" {
  name        = "${var.deployment_unique_name}-r53-resolver-sg"
  description = "Allow outbound DNS"
  vpc_id      = var.aws_vpc_id

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.aws_vpc_cidr]
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.aws_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.deployment_unique_name}" })
}

resource "aws_route53_resolver_endpoint" "outbound" {
  name                   = "${var.deployment_unique_name}-outbound"
  direction              = "OUTBOUND"
  //resolver_endpoint_type = "IPV4"
  security_group_ids     = [aws_security_group.r53_resolver_sg.id]

  dynamic "ip_address" {
    for_each = local.resolver_subnets
    content {
      subnet_id = ip_address.value
    }
  }

  tags = merge(var.tags, { Name = "${var.deployment_unique_name}" })
}

resource "aws_route53_resolver_rule" "forward" {
  name        = "${var.deployment_unique_name}-forward-${replace(var.fqdn, ".", "-")}"
  domain_name = var.fqdn
  rule_type   = "FORWARD"
  #rule_action          = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound.id

  dynamic "target_ip" {
    for_each = var.target_ips
    content {
      ip = target_ip.value
    }
  }

  tags = merge(var.tags, { Name = "${var.deployment_unique_name}" })
}

resource "aws_route53_resolver_rule_association" "vpc_association" {
  resolver_rule_id = aws_route53_resolver_rule.forward.id
  vpc_id           = var.aws_vpc_id
}
