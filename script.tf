terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

#=======================================================================
# Azure ad tenant used to authenticate users to the clusters and for managed identity
#=======================================================================
variable "tenant_id" {
  type = string
  default = "" #Tenant ID 
}

#=======================================================================
# Variable to store both regions which should be used 
#=======================================================================
variable "availableRegions" {
  type = map
  defaults = {
    "CH-NO" = "Switzerland North"
    "CH-WE" = "Switzerland West"
  }
}

#=======================================================================
# Azure resource providers which are required for the aks enivironment
#=======================================================================

# Ensures Azure Active Director is usable in the subscription
resource "azurerm_resource_provider_registration" "MicrosoftAAD" {
  name = "Microsoft.AAD"
}

# Ensures Azure Virtual Machines are usable in the subscription
# Also enables support for virtual machine scale set which are used by aks node pools
resource "azurerm_resource_provider_registration" "MicrosoftCompute" {
  name = "Microsoft.Compute"
}

# Ensures Azure Container Instances are usable in the subscription
# Required for virtual nodes in aks which are used for repid scaling of pods into ACI instances
resource "azurerm_resource_provider_registration" "MicrosoftContainerInstance" {
  name = "Microsoft.ContainerInstance"
}

# Ensures Azure Container Registry is usable in the subscription
# Required to store container images which are pulled by the aks clusters and ACI
resource "azurerm_resource_provider_registration" "MicrosoftContainerRegistry" {
  name = "Microsoft.ContainerRegistry"
}

# Ensures Azure Kubernetes Service is usable in the subscription
resource "azurerm_resource_provider_registration" "MicrosoftContainerService" {
  name = "Microsoft.ContainerService"
}

# Ensures Azure Key Vault is usable in the subscription
# Required to store encryption key used by the disk encryption set which stores os disks and aks volumes
resource "azurerm_resource_provider_registration" "MicrosoftKeyVault" {
  name = "Microsoft.KeyVault"
}

# Ensures Azure Managed Identity is usable in the subscription
# Required to authenticate aks node pools to container registry and key vault
resource "azurerm_resource_provider_registration" "MicrosoftManagedIdentity" {
  name = "Microsoft.ManagedIdentity"
}

# Ensures Azure Maintanance is usable in the subscription
# Required to set a maintanance window and policy for the aks clusters
resource "azurerm_resource_provider_registration" "MicrosoftMaintenance" {
  name = "Microsoft.Maintenance"
}

# Ensures Azure Storage is usable in the subscription
# Required to create os disks and aks volumes which are stored in azure disk and azure file storage
resource "azurerm_resource_provider_registration" "MicrosoftStorage" {
  name = "Microsoft.Storage"
}

resource "azurerm_resource_group" "garseb-rg-1" {
  name     = "garseb-rg-1"
  location = var.availableRegions["CH-NO"]
}

#=======================================================================
# Azure key vault used to encrypt aks node pool os disks and aks volumes
#=======================================================================
resource "azurerm_container_registry" "garseb-acr-chno-1" {
  depends_on = [
    azurerm_resource_group.garseb-rg-1
  ]

  name                = "garseb--acr1-chno"
  resource_group_name = azurerm_resource_group.garseb-rg-1.name
  location            =  var.availableRegions["CH-NO"]
  sku                 = "Premium"
  admin_enabled       = false
  anonymous_pull_enabled = false

  tags = {
    "environment" = "aks cluster"
    "costcenter" = "Klärag AG AKS Cluster"
    "administration" = "EAS AG"
  }

  zone_redundancy_enabled = true # Enabled support for availabilty zones in the primary region

  georeplications {
    location                = var.availableRegions["CH-WE"] # Defines the region of the replicated ACR
    zone_redundancy_enabled = true # Enables support for availabilty zones in secondary region
    tags                    = {}
  }

  network_rule_set {
    default_action = "Deny"
    virtual_network {
      action = "Allow"
      subnet_id = "" # ID von AKS Cluster Node Pool
    }
  }

  public_network_access_enabled = false
  
  retention_policy {
    enabled = true
    days = 30
  }

  encryption {

  }
}


#=======================================================================
# Azure key vault used to encrypt aks node pool os disks and aks volumes
#================
resource "azurerm_virtual_network" "garseb-vnet-chno-1" {
  depends_on = [
    azurerm_resource_group.garseb-rg1-aks
  ]

  name                = "example-network"
  resource_group_name = azurerm_resource_group.example.name
  location            = var.availableRegions["CH-NO"]
  address_space       = ["10.0.0.0/16"]
}

#=======================================================================
# Azure key vault used to encrypt aks node pool os disks and aks volumes
#================
resource "azurerm_virtual_network" "garseb-vnet-chwe-2" {
  depends_on = [
    azurerm_resource_group.garseb-rg1-aks
  ]

  name                = "example-network"
  resource_group_name = azurerm_resource_group.example.name
  location            = var.availableRegions["CH-NO"]
  address_space       = ["10.0.0.0/16"]
}


#=======================================================================
# Azure key vault used to encrypt aks node pool os disks and aks volumes
#=======================================================================
resource "azurerm_key_vault" "garseb-keyvault-chno-1" {
    depends_on = [
      azurerm_resource_group.garseb-rg1-aks
    ]

    name                        = "examplekeyvault"
    location                    = var.availableRegions["CH-NO"]
    resource_group_name         = azurerm_resource_group.garseb-rg1-aks
    
    enabled_for_disk_encryption = true
    
    #enable_rbac_authorization = false
    #soft_delete_retention_days  = 7
    #purge_protection_enabled    = true
    #public_network_access_enabled = false

    sku_name = "standard"
}

#=======================================================================
# Key stored in key kault used for disk encryption set
#=======================================================================
resource "azurerm_key_vault_key" "garseb-adekey1-aks" {
    depends_on = [
        azurerm_resource_group.garseb-rg1-aks,
        azurerm_key_vault.garseb-keyvault-chno-1
    ]

    name         = "generated-certificate"
    key_vault_id = azurerm_key_vault.garseb-keyvault-chno-1.id
    key_type     = "RSA"
    key_size     = 2048

    key_opts = [
        "decrypt",
        "encrypt",
        "sign",
        "unwrapKey",
        "verify",
        "wrapKey",
    ]
}

#==================================================================================================
# Disk encryption set used to encrypt aks node os disks and aks volumes in switzerland north
#==================================================================================================
resource "azurerm_disk_encryption_set" "garseb-aksadekeyset-chno-1" {
    depends_on = [
        azurerm_resource_group.garseb-rg1-aks,
        azurerm_key_vault.garseb-keyvault-chno-1,
        azurerm_key_vault_key.garseb-adekey1-aks
    ]

    name                = "diskencryptionset"
    resource_group_name = azurerm_resource_group.garseb-rg1-aks
    location            = var.availableRegions["CH-NO"]
    key_vault_key_id    = azurerm_key_vault.garseb-keyvault-chno-1.id

    identity {
        type = "SystemAssigned"
    }
}

#==================================================================================================
# Disk encryption set used to encrypt aks node os disks and aks volumes in switzerland west
#==================================================================================================
resource "azurerm_disk_encryption_set" "garseb-aksadekeyset-chwe-2" {

}


#==================================================================================================
# Application Gateway used as an aks ingress controller in the switzerland north cluster
#==================================================================================================
azurerm_application_gateway "" {

}

#==================================================================================================
# Application Gateway used as an aks ingress controller in the switzerland west cluster
#==================================================================================================
azurerm_application_gateway "" {

}

#==================================================================================================
# Defines the azure kubernetes service cluster in the switzerland north region
#==================================================================================================
azurerm_kubernetes_cluster "garseb-aks-chno-1" {
  name = ""
  location = ""
  resource_group_name = ""

  azure_policy_enabled = true

  private_cluster_enabled = true
  role_based_access_control_enabled = true
  sku_tier = "Paid"
  local_account_disabled = true
  enable_auto_scaling = true
  disk_encryption_set_id = ""


  tags =  [

  ]

  identity {
    
  }

  default_node_pool {
    max_pods = ""
    kubelet_disk_type = "OS"
    os_disk_size_gb = "30"
    os_disk_type = "Managed"
    type = "VirtualMachineScaleSets"
    max_count = 10
    min_count = 1
    node_count = 1
  }

  aci_container_linux {
    subnet_name = ""
  }
  
  auto_scaler_profile {

  }

  api_server_authorized_ip_ranges = [

  ]

  azure_active_directory_role_based_access_control {

  }

  disk_encryption_set_id = ""

  ingress_application_gateway {
    gateway_id = ""
    gateway_name = ""
    subnet_cidr = ""
    subnet_id = ""
  }

  maintenance_window {
    allowed {
      day = "Sunday"
      hours = 
    }
    not_allowed {
      start = ""
      end = ""
    }
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    outbound_type = "loadBalancer"
  }
}


#==================================================================================================
# Defines the azure kubernetes service cluster in the switzerland north region
#==================================================================================================
azurerm_kubernetes_cluster "garseb-aks-chwe-2" {

}
