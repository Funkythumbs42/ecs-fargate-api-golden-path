locals {
  tags = merge(
    {
      Platform  = var.name
      ManagedBy = "terraform"
      Module    = "platform"
    },
    var.tags,
  )

  # Single NAT in the first public subnet. This is an example stub, not HA NAT.
  nat_az_index = 0
}
