run "dev_address_and_naming_contract" {
  command = plan
  assert {
    condition     = output.prefix == "mqgen-ai-dev-eus2"
    error_message = "The dev naming contract changed."
  }
  assert {
    condition     = output.subnets.host == "10.41.0.0/24" && output.subnets.container == "10.41.1.0/24"
    error_message = "Host and container must occupy the planned distinct /24 ranges."
  }
  assert {
    condition     = output.usable_addresses == 251 && output.tags.costcenter == "10999"
    error_message = "Address capacity or ownership metadata is incorrect."
  }
}
run "prod_changes_names_not_ownership" {
  command = plan
  variables { environment = "prod" }
  assert {
    condition     = output.prefix == "mqgen-ai-prod-eus2" && output.tags.owner == "mqgen-it"
    error_message = "Environment should change the name while preserving the owner."
  }
}
run "reject_misspelled_environment" {
  command = plan
  variables { environment = "production" }
  expect_failures = [var.environment]
}
