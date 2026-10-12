variable "name_prefix" {
  description = "Prefix for naming resources created by the spoke module."
  type        = string
  default     = "langfuse-spoke"
}

variable "vpc_id" {
  description = "The VPC ID of the spoke agent where the VPC Endpoint will be provisioned."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs in the spoke VPC where Endpoint network interfaces will be created."
  type        = list(string)
}

variable "endpoint_service_name" {
  description = "The service name of the Central Langfuse PrivateLink Endpoint Service (e.g. com.amazonaws.vpce.eu-central-1.vpce-svc-XXXX)."
  type        = string
}

variable "port" {
  description = "TCP port on which the endpoint receives Langfuse traffic."
  type        = number
  default     = 3000
}

variable "agent_security_group_ids" {
  description = "Optional list of agent security group IDs allowed to access the endpoint."
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "Optional list of CIDR blocks allowed to access the endpoint. If empty and agent_security_group_ids is empty, defaults to the spoke VPC CIDR."
  type        = list(string)
  default     = []
}

variable "dns_zone_id" {
  description = "Optional Route53 Private Hosted Zone ID in the spoke VPC to create a friendly CNAME (e.g. langfuse.internal.bayer)."
  type        = string
  default     = null
}

variable "dns_record_name" {
  description = "DNS record name to create in the Private Hosted Zone."
  type        = string
  default     = "langfuse"
}

variable "tags" {
  description = "Tags to assign to the spoke endpoint and resources."
  type        = map(string)
  default     = {}
}
