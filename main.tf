

provider "aws" {
    region = "us-east-2"
    access_key = var.aws_user_key 
    secret_key = var.aws_secret_key
}

variable "aws_user_key"{}
variable "aws_secret_key"{}
variable "aws_region" {}
variable "aws_domain"{}

resource "aws_vpc" "hml-vpc" {
    cidr_block = "10.10.0.0/24"
}


resource "aws_subnet" "hml-subnet-1" {
    vpc_id              = aws_vpc.hml-vpc.id
    cidr_block          = "10.10.0.0/25"
    availability_zone   = var.aws_region
  
}

resource "aws_network_interface" "hml-nic" {
  subnet_id   = aws_subnet.hml-subnet-1.id
  private_ips = ["10.10.0.10"]

  tags = {
    Name = "hml_network_interface"
  }
}

resource "aws_eip" "lb" {
  instance = aws_instance.hml-instancia.id
  vpc      = true
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

resource "aws_acm_certificate" "hml-cert" {
  domain_name       = var.aws_domain
  validation_method = "DNS"
}

data "aws_route53_zone" "external" {
  name = var.aws_domain
}
resource "aws_route53_record" "rec" {
  name    = var.aws_domain
  type    = "A"
  zone_id = data.aws_route53_zone.external.zone_id
  records = [aws_eip.lb.publi_ip]
  ttl     = "300"
}

resource "aws_acm_certificate_validation" "hml-valid" {
  certificate_arn = aws_acm_certificate.hml-cert.arn
  validation_record_fqdns = [
    aws_route53_record.rec.fqdn,
  ]
}

resource "aws_elb" "hml-elb" {
  name               = "hml-elb"
  availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]

  access_logs {
    bucket        = "hml-promo"
    bucket_prefix = "hml-promo"
    interval      = 60
  }

  listener {
    instance_port     = 8000
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port      = 8000
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = aws_acm_certificate.hml-cert.arn
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:8000/"
    interval            = 30
  }

  instances                   = [aws_instance.hml-instancia.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "hmlpromo-elb"
  }
}