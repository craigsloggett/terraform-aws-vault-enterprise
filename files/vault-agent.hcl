pid_file = "/opt/vault/agent/agent.pid"

vault {
  address = "https://127.0.0.1:8200"
  ca_cert = "/opt/vault/tls/ca.crt"
}

auto_auth {
  method "aws" {
    mount_path = "auth/aws"
    config = {
      type = "iam"
      role = "vault-server"
    }
  }

  sink "file" {
    config = {
      path = "/opt/vault/agent/token"
    }
  }
}

template {
  source      = "/etc/vault-agent/server.crt.ctmpl"
  destination = "/opt/vault/tls/server.crt"
  perms       = "0640"
  command     = "systemctl kill -s HUP vault.service"
}

template {
  source      = "/etc/vault-agent/server.key.ctmpl"
  destination = "/opt/vault/tls/server.key"
  perms       = "0640"
}
