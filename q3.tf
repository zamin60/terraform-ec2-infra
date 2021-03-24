provider "aws" {
  region = "us-east-1"
}
terraform {
  backend "s3" {
    bucket = "var.bucketname"
    key = "terraform"
    region = "us-east-1"
    dynamodb_table = "terraform-lock"
  }
}

resource "aws_security_group" "my_nginx_sg" {
  name        = "my_nginx_sg"
  description = "Allow http for nginx"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "TLS from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]

  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "http_for_nginx"
  }
}

resource "aws_instance" "test" {
  ami           = "var.ami"
  instance_type = "t2.micro"
  vpc_security_group_ids    = [aws_security_group.my_nginx_sg.id]
   associate_public_ip_address = "true"
  subnet_id = aws_subnet.my-subnet-1.id
  }
  
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main"
  }
}

#route_table
resource "aws_route_table" "route-table" {
  vpc_id = aws_vpc.main.id
  depends_on = [aws_internet_gateway.gw ]

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "route-table"
}
}

#route_table_association

resource "aws_route_table_association" "associate" {
  subnet_id      = aws_subnet.my-subnet-1.id
  route_table_id = aws_route_table.route-table.id
}

resource "aws_route_table_association" "associate-2" {
  subnet_id      = aws_subnet.my-subnet-2.id
  route_table_id = aws_route_table.route-table.id
}

resource "aws_subnet" "my-subnet-1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "Main"
  }
}

resource "aws_subnet" "my-subnet-2" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "Main"
  }
}  
resource "aws_lb" "my-alb" {

  depends_on = [aws_vpc.main,aws_subnet.my-subnet-1,aws_subnet.my-subnet-2]
  name               = "my-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.my_nginx_sg.id]
  subnets            = ["${aws_subnet.my-subnet-1.id}", "${aws_subnet.my-subnet-2.id}"]
  tags = {
    Environment = "test"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.my-alb.arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb-target.arn
  }
}

resource "aws_lb_listener_rule" "static" {
  listener_arn = aws_lb_listener.front_end.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb-target.arn
  }
  condition {
    path_pattern {
      values = ["/"]
    }
  } 
} 

resource "aws_lb_target_group" "alb-target" {
  name     = "alb-target"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}



resource "aws_lb_target_group_attachment" "test" {
  depends_on = [aws_lb.my-alb,aws_lb_target_group.alb-target,aws_instance.test]
  target_group_arn = aws_lb_target_group.alb-target.arn
  target_id        = aws_instance.test.id
  port             = 80
}