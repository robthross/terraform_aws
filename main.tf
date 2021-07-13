provider "aws" {
    region = "us-east-2"
    access_key = "{{ USER_KEY }}"
    secret_key = "{{ SECRET_KEY }}"
}

resource "aws_vpc" "hml-vpc" {
    cidr_block = "10.10.0.0/24"
}


resource "aws_subnet" "hml-subnet-1" {
    vpc_id              = aws_vpc.hml-vpc.id
    cidr_block          = "10.10.0.0/25"
    availability_zone   = "us-east-2a"
  
}

resource "aws_network_interface" "hml-nic" {
  subnet_id   = aws_subnet.hml-subnet-1.id
  private_ips = ["10.10.0.10"]

  tags = {
    Name = "hml_network_interface"
  }
}

resource "aws_instance" "hml-instancia" {
  ami           = "ami-0233c2d874b811deb" 
  instance_type = "t2.micro"

  network_interface {
    network_interface_id = aws_network_interface.hml-nic.id
    device_index         = 0
  }
}

resource "aws_security_group" "hml-sg-1" {
  name        = "hml_tls"
  description = "Permite TLS inbound trafego"
  vpc_id      = aws_vpc.hml-vpc.id

  ingress {
    description      = "TLS from VPC"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = [aws_vpc.hml-vpc.cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "permite_tls"
  }
}

resource "aws_elasticache_cluster" "hml-redis" {
  cluster_id           = "cluster-hml"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis3.2"
  engine_version       = "3.2.10"
  port                 = 6379
}

module "nlb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 6.0"

  name = "hml-nlb"

  load_balancer_type = "network"

  vpc_id  = aws_vpc.hml-vpc.id
  

  access_logs = {
    bucket = "hml-nlb-logs"
  }

  target_groups = [
    {
      name_prefix      = "pref-"
      backend_protocol = "TCP"
      backend_port     = 80
      target_type      = "ip"
    }
  ]

  https_listeners = [
    {
      port               = 443
      protocol           = "TLS"
      certificate_arn    = "arn:aws:iam::123456789012:server-certificate/test_cert-123456789012"
      target_group_index = 0
    }
  ]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "TCP"
      target_group_index = 0
    }
  ]

  tags = {
    Environment = "hml-test"
  }
}