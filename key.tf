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

resource "null_resource" "gen_e_n" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = "echo -n ${azurerm_key_vault_key.generated.e} | base64 --decode | xxd -p -u | tr -d '\n' > hex_exponent && echo -n ${azurerm_key_vault_key.generated.n} | base64 --decode | xxd -p -u | tr -d '\n' > hex_modulus"
  }
}

data "local_file" "hex_exponent" {
    filename = "hex_exponent"

    depends_on = [null_resource.gen_e_n]
}

data "local_file" "hex_modulus" {
    filename = "hex_modulus"

    depends_on = [null_resource.gen_e_n]
}

data "template_file" "asn1" {
  template = "${file("def.asn1.tpl")}"
  vars = {
    hex_exponent_value = data.local_file.hex_exponent.content
    hex_modulus_value = data.local_file.hex_modulus.content
  }

  depends_on = [data.local_file.hex_exponent, data.local_file.hex_modulus]
}

resource "local_file" "asn1_filled" {
  content  = data.template_file.asn1.rendered
  filename = "def.asn1.tpl.filled"
}

resource "null_resource" "gen_key_file" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = "openssl asn1parse -genconf def.asn1.tpl.filled -out pubkey.der -noout && openssl rsa -in pubkey.der -inform der -pubin -out pubkey.pem && ssh-keygen -f pubkey.pem -i -mPKCS8 > pubkey.rsa"
  }

  depends_on = [data.template_file.asn1]
}
