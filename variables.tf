variable "aws_region" {
}
variable "aws_profile" {
}
variable "name_prefix" {
}
variable "vpc_cidr_block" {
  # default = "10.0.0.0/16"
}
variable "my_ip" {
  default = "73.142.34.8/32"
}
variable "security_cidr" {
  default = "0.0.0.0/0"
}
variable "ami_id" {
  default = "ami-04c352314111a4591"
}
variable "instance_type" {
  default = "t2.micro"
}
variable "key_name" {
  default = "ec2"
}

