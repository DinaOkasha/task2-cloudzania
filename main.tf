terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"  # Specify the appropriate version for your use case
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"  # Specify the appropriate version for local provider
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"  # Specify the appropriate version for TLS provider
    }
  }

  required_version = ">= 1.0"  # Specify the appropriate Terraform version

 
}


# Configure the AWS Provider
provider "aws" {
  region = "eu-west-1"
}

# Create a VPC
resource "aws_vpc" "task2_vpc" {
  cidr_block = "10.10.0.0/16"
  enable_dns_support = true  # Enable DNS resolution
  enable_dns_hostnames = true # Enable DNS hostnames
  tags = {
    Name = "task2_vpc"
  }
}

variable "vpc_availability_zones" {
  type        = list(string)
  description = "Availability Zones"
  default     = ["eu-west-1a", "eu-west-1b"]
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.task2_vpc.id

  tags = {
    Name = "task2_vpc-igw"
  }

}
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.task2_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}



resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.task2_vpc.id
  cidr_block              = "10.10.1.0/24"  # Set the CIDR block
  availability_zone       = "eu-west-1a"   # Specify the availability zone
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-a"  # Set a static name for the public subnet
  }
}

# Associate the subnet with the route table
resource "aws_route_table_association" "public_subnet_a_assoc" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}


resource "tls_private_key" "rsa_4096" {
  algorithm = "RSA"
  rsa_bits  = 4096
}


// Create Key Pair for Connecting EC2 via SSH
resource "aws_key_pair" "key_pair" {
  key_name   = "task2-key"
  public_key = tls_private_key.rsa_4096.public_key_openssh
}

// Save PEM file locally
resource "local_file" "private_key" {
  content  = tls_private_key.rsa_4096.private_key_pem
  filename = "task2-key"
}

resource "aws_security_group" "ec2_sg" {
  vpc_id = aws_vpc.task2_vpc.id  # Associate the security group with your VPC

  // Security group description
  description = "Allow HTTP, HTTPS, and SSH inbound traffic"

  // Inbound rules
  ingress {
    from_port   = 22    // Allow SSH
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // Allow from anywhere (be cautious)
  }
  ingress {
    from_port   = 8080    // Allow HTTP
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // Allow from anywhere
  }
  ingress {
    from_port   = 80    // Allow HTTP
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // Allow from anywhere
  }

  ingress {
    from_port   = 443   // Allow HTTPS
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // Allow from anywhere
  }

  // Egress rule to allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  // All protocols
    cidr_blocks = ["0.0.0.0/0"] // Allow all outbound traffic
  }

  tags = {
    Name = "ec2-security-group"
  }
}

# Allocate a static Elastic IP
resource "aws_eip" "static_eip" {
  vpc = true  # This ensures the Elastic IP is for use in a VPC

  tags = {
    Name = "Static-Elastic-IP"
  }
}

# Create A record for ec2-docker.everyoneget.click
resource "aws_route53_record" "ec2_docker_record" {
  zone_id = "Z0770151337G7J04A4517"   # Replace with your Route 53 hosted zone ID
  name    = "ec2-docker.everyoneget.click"
  type    = "A"
  ttl     = 300
  records = [aws_eip.static_eip.public_ip]  # Use the static Elastic IP
}

# Create A record for ec2-instance.everyoneget.click
resource "aws_route53_record" "ec2_instance_record" {
  zone_id = "Z0770151337G7J04A4517"   # Replace with your Route 53 hosted zone ID
  name    = "ec2-instance.everyoneget.click"
  type    = "A"
  ttl     = 300
  records = [aws_eip.static_eip.public_ip]  # Use the static Elastic IP
}

resource "aws_instance" "ec2_instance" {
  ami           = "ami-02f64c390601e5f36" # Use the latest stable AMI ID for your region
  instance_type = "t2.micro"
  key_name      = aws_key_pair.key_pair.key_name

  # Attach the instance to the public subnet
  subnet_id = aws_subnet.public_subnet_a.id # Reference the public subnet
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  tags = {
    Name = "EC2-Docker-NGINX"
  }

  # User data for installing Docker, NGINX, and configuring them
  # User data for installing Docker, NGINX, and configuring them
 user_data = <<-EOF
              #!/bin/bash
             
              sudo yum update -y
              
              # Install Docker
              sudo yum install -y docker
              sudo service docker start

              # Pull the NGINX Docker image and create a basic HTML page
              sudo docker pull nginx:alpine
              sudo sleep 5
              sudo docker run -d --name my-nginx -p 8080:80 nginx:alpine && sudo docker exec my-nginx sh -c 'echo "Namaste from Container" > /usr/share/nginx/html/index.html'

              # Install NGINX from Amazon Linux Extras
              sudo amazon-linux-extras enable nginx1
              sudo yum install -y nginx
              sudo systemctl start nginx
              sudo systemctl enable nginx
              
              # Create the NGINX configuration file
              sudo bash -c 'cat <<EOF_NGINX > /etc/nginx/conf.d/my_sites.conf
                 server {
                     listen 80;
                     server_name ec2-instance.everyoneget.click;

                     location / {
                         return 200 "Hello from Instance";
                         add_header Content-Type text/plain;
                     }  # Closing brace for the first location block
                 }  # Closing brace for the first server block

                 server {
                     listen 80;
                     server_name ec2-docker.everyoneget.click;

                     location / {
                         proxy_pass http://localhost:8080;  # Forward requests to the Docker container
                         proxy_set_header Host \$host;
                         proxy_set_header X-Real-IP \$remote_addr;
                         proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
                         proxy_set_header X-Forwarded-Proto \$scheme;
                     }  # Closing brace for the second location block
                 }  # Closing brace for the second server block
              EOF_NGINX'

              # Install EPEL repository for Certbot
              sudo amazon-linux-extras install epel -y

              # Install Certbot and the NGINX plugin
              sudo yum install -y certbot-nginx

              # Obtain SSL certificates
              sudo certbot --nginx -d ec2-instance.everyoneget.click -d ec2-docker.everyoneget.click --non-interactive --agree-tos --email drdinaokasha@gmail.com

              # Redirect HTTP to HTTPS
              sudo bash -c 'cat <<EOF_REDIRECT >> /etc/nginx/conf.d/my_sites.conf
                 server {
                     listen 80;
                     server_name ec2-instance.everyoneget.click ec2-docker.everyoneget.click;
                     return 301 https://\$host\$request_uri;
                 }
              EOF_REDIRECT'

              # Test NGINX configuration
              sudo nginx -t

              # Restart NGINX to apply the new configuration
              sudo systemctl restart nginx
EOF

}

# Associate the static Elastic IP with the EC2 instance
resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.ec2_instance.id
  allocation_id = aws_eip.static_eip.id
}
