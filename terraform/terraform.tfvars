region             = "us-east-1"
vpc_id             = "vpc-0e2b7d69"
subnet_id          = "subnet-4a11f267"
eip_allocation_id  = "eipalloc-0938e39b8988b3bc5"
instance_type      = "t3.xlarge"
name_prefix        = "demo-jira"
root_volume_size   = 60
ansible_user       = "ansible"

tags = {
  Project = "jira-demo"
  Owner   = "platform"
}
