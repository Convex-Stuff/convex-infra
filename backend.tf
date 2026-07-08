terraform {
  backend "local" {
    path = "/home/atlantis/.atlantis/tfstate/convex-infra/terraform.tfstate"
  }
}
