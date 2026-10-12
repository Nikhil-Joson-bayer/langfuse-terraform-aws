output "endpoint_id" {
  description = "The ID of the Interface VPC Endpoint created in the spoke VPC."
  value       = aws_vpc_endpoint.langfuse.id
}

output "endpoint_dns" {
  description = "The regional DNS hostname of the Interface VPC Endpoint (use this in agent configuration)."
  value       = lookup(aws_vpc_endpoint.langfuse.dns_entry[0], "dns_name")
}

output "endpoint_network_interface_ids" {
  description = "The list of network interface IDs created for the VPC endpoint."
  value       = aws_vpc_endpoint.langfuse.network_interface_ids
}

output "security_group_id" {
  description = "The security group ID assigned to the VPC endpoint."
  value       = aws_security_group.endpoint.id
}
