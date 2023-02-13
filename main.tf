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

# Create a resource group
resource "azurerm_resource_group" "NeekTech-rg" {
  name     = "NeekTech-resources"
  location = "UK South"

  tags = {
    enviroment : "dev"
  }
}

# create a Virtual network
resource "azurerm_virtual_network" "NeekTech-vn" {
  name                = "NeekTech-network"
  resource_group_name = azurerm_resource_group.NeekTech-rg.name
  location            = azurerm_resource_group.NeekTech-rg.location
  address_space       = ["192.168.0.0/16"]

  tags = {
    enviroment : "dev"
  }
}

# create a subnet
resource "azurerm_subnet" "NeekTech-subnet" {
  name                 = "NeekTech-subnet"
  resource_group_name  = azurerm_resource_group.NeekTech-rg.name
  virtual_network_name = azurerm_virtual_network.NeekTech-vn.name
  address_prefixes     = ["192.168.1.0/24"]
}

# create an NSG
resource "azurerm_network_security_group" "NeekTech-NSG" {
  name                = "NeekTech-NSG"
  location            = azurerm_resource_group.NeekTech-rg.location
  resource_group_name = azurerm_resource_group.NeekTech-rg.name

  tags = {
    enviroment : "dev"
  }
}

# # create the rules for the nsg
resource "azurerm_network_security_rule" "NeekTech_Nsg_Rule" {
  name                        = "NeekTech_Nsg_Rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "*"
  destination_address_prefix  = "192.168.1.4"
  resource_group_name         = azurerm_resource_group.NeekTech-rg.name
  network_security_group_name = azurerm_network_security_group.NeekTech-NSG.name
}

# associate the nsg to the subnet
resource "azurerm_subnet_network_security_group_association" "NeekTech-Association" {
  subnet_id                 = azurerm_subnet.NeekTech-subnet.id
  network_security_group_id = azurerm_network_security_group.NeekTech-NSG.id
}

# create a public IP for the vm
resource "azurerm_public_ip" "NeekTech-ip" {
  name                = "NeekTech-ip"
  resource_group_name = azurerm_resource_group.NeekTech-rg.name
  location            = azurerm_resource_group.NeekTech-rg.location
  allocation_method   = "Dynamic"
  # sku = "Standard"

  tags = {
    environment = "dev"
  }
}

# create a public IP for the bastion
resource "azurerm_public_ip" "NeekTech-bastion-ip" {
  name                = "NeekTech-bastion-ip"
  resource_group_name = azurerm_resource_group.NeekTech-rg.name
  location            = azurerm_resource_group.NeekTech-rg.location
  allocation_method   = "Static"
  sku = "Standard"

  tags = {
    environment = "dev"
  }
}

// create a NIC for the vm
resource "azurerm_network_interface" "NeekTech-Nic" {
  name                = "NeekTech-NIC"
  location            = azurerm_resource_group.NeekTech-rg.location
  resource_group_name = azurerm_resource_group.NeekTech-rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.NeekTech-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.NeekTech-ip.id
  }

  tags = {
    enviroment : "dev"
  }
}

# create the VM
resource "azurerm_linux_virtual_machine" "NeekTech-vm" {
  name                = "NeekTech-vm"
  resource_group_name = azurerm_resource_group.NeekTech-rg.name
  location            = azurerm_resource_group.NeekTech-rg.location
  size                = "Standard_B1s"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.NeekTech-Nic.id,
  ]

  custom_data = filebase64("customdata.tpl")

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/azurevmkey.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  provisioner "local-exec" {
    command = templatefile("${var.host_os}-ssh-script.tpl", {
      hostname     = self.public_ip_address,
      user         = "adminuser",
      identityfile = "~/.ssh/azurevmkey"
    })
    interpreter = var.host_os == "windows" ? ["powershell", "-Command"] : ["bash", "-c"]
  }

  tags = {
    enviroment : "dev"
  }
}

# create a bastion subnet
resource "azurerm_subnet" "NeekTech-bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.NeekTech-rg.name
  virtual_network_name = azurerm_virtual_network.NeekTech-vn.name
  address_prefixes     = ["192.168.2.0/24"]
}

# create a bastion host
resource "azurerm_bastion_host" "NeekTech_Bastion_Host" {
  name                = "NeekTech_Bastion_Host"
  location            = azurerm_resource_group.NeekTech-rg.location
  resource_group_name = azurerm_resource_group.NeekTech-rg.name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.NeekTech-bastion.id
    public_ip_address_id = azurerm_public_ip.NeekTech-bastion-ip.id
  }
}


# data source to query and fetch the public IP
data "azurerm_public_ip" "NeekTech-ip-data" {
  name                = azurerm_public_ip.NeekTech-ip.name
  resource_group_name = azurerm_resource_group.NeekTech-rg.name
}

output "ip_address_instance" {
  value = "${azurerm_linux_virtual_machine.NeekTech-vm.name}:${data.azurerm_public_ip.NeekTech-ip-data.ip_address}"

}
