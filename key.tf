data "azurerm_client_config" "current" {
}

provider "azurerm" {
  version = "=2.0.0"
  features {}
}

resource "azurerm_resource_group" "example" {
  name     = "my-resource-group"
  location = "West US"
}

resource "random_id" "server" {
  keepers = {
    ami_id = 1
  }

  byte_length = 8
}

resource "azurerm_key_vault" "example" {
  name                = "pmk-keyvaultkeyexample-1"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name = "premium"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "create",
      "get",
    ]

    secret_permissions = [
      "set",
    ]
  }

  tags = {
    environment = "Production"
  }
}

resource "azurerm_key_vault_key" "generated" {
  name         = "generated-certificate"
  key_vault_id = azurerm_key_vault.example.id
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

output public_key_exponent {
  value = azurerm_key_vault_key.generated.e
}

output public_key_modulus {
  value = azurerm_key_vault_key.generated.n
}

# resource "local_file" "exponent" {
#   content  = azurerm_key_vault_key.generated.e
#   filename = "exponent.txt"
# }

# resource "local_file" "modulus" {
#   content  = azurerm_key_vault_key.generated.n
#   filename = "modulus.txt"
# }


resource "null_resource" "gen_e_n" {
#   triggers = {
#     cluster_instance_ids = "${join(",", aws_instance.cluster.*.id)}"
#   }

  provisioner "local-exec" {
    command = "echo -n ${azurerm_key_vault_key.generated.e} | base64 --decode | xxd -p -u | tr -d \\n > hex_exponent && echo -n ${azurerm_key_vault_key.generated.n} | base64 --decode | xxd -p -u | tr -d \\n > hex_modulus"
  }
}

data "local_file" "hex_exponent" {
    filename = "hex_exponent"

    depends_on = [null_resource.gen_e_n]
}

data "local_file" "hex_modulus" {
    filename = "hex_exponent"

    depends_on = [null_resource.gen_e_n]
}

data "template_file" "asn1" {
  template = "${file("def.asn1.tpl")}"
  vars = {
    hex_exponent_value = data.local_file.hex_exponent.content
    hex_modulus_value = data.local_file.hex_modulus.content
  }
}

resource "local_file" "asn1_filled" {
  content  = data.template_file.asn1.rendered
  filename = "def.asn1.tpl.filled"
}

resource "null_resource" "gen_key_file" {
#   triggers = {
#     cluster_instance_ids = "${join(",", aws_instance.cluster.*.id)}"
#   }

  provisioner "local-exec" {
    command = "openssl asn1parse -genconf def.asn1.tpl.filled -out pubkey.der -noout && openssl rsa -in pubkey.der -inform der -pubin -out pubkey.pem && ssh-keygen -f pubkey.pem -i -mPKCS8 > pubkey.rsa"
  }
}

data "local_file" "rsa_pub_key" {
    filename = "pubkey.rsa"

    depends_on = [null_resource.gen_key_file]
}

# output rsa_pub_key {
#     value = data.local_file.rsa_pub_key
# }
