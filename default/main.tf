terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

locals {
  username = data.coder_workspace_owner.me.name
  images = {
    node     = docker_image.node,
    python   = docker_image.python,
    java     = docker_image.java,
    c        = docker_image.c,
    go       = docker_image.go,
    rust     = docker_image.rust,
    # docker   = docker_image.docker,
    embedded = docker_image.embedded,
    base     = docker_image.base,
  }
}

data "coder_provisioner" "me" {}

provider "docker" {}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<-EOT
    set -e
    
    # Prepare user home with default files on first start.
    # if [ ! -f ~/.init_done ]; then
    #   cp -rT /etc/skel ~
    #   touch ~/.init_done
    # fi

    # Install the latest code-server.
    # Append "--version x.x.x" to install a specific version of code-server.
    # curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server

    # Start code-server in the background.
    # /tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &
  EOT

  # These environment variables allow you to make Git commits right away after creating a
  # workspace. Note that they take precedence over configuration defined in ~/.gitconfig!
  # You can remove this block if you'd prefer to configure Git manually or using
  # dotfiles. (see docs/dotfiles.md)
  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
  }
}

data "coder_parameter" "git_repo" {
  name         = "git_repo"
  display_name = "Git repository"
  default      = "https://github.com/katorlys/Template"
}

module "git_clone" {
  source   = "registry.coder.com/modules/git-clone/coder"
  version  = "1.0.12"
  agent_id = coder_agent.main.id
  url      = data.coder_parameter.git_repo.value
  base_dir = "/workspace"
}

data "coder_parameter" "docker_image" {
  icon        = "/icon/docker.png"
  name        = "Workspace Image"
  description = "Which workspace image do you want to use?"
  type        = "string"
  default     = "base"
  mutable     = true

  option {
    icon  = "/icon/nodejs.svg"
    name  = "Node.js"
    value = "node"
  }
  option {
    icon  = "/icon/python.svg"
    name  = "Python"
    value = "python"
  }
  option {
    icon  = "/icon/java.svg"
    name  = "Java"
    value = "java"
  }
  option {
    icon  = "/icon/cpp.svg"
    name  = "C/C++"
    value = "c"
  }
  option {
    icon  = "/icon/go.svg"
    name  = "Go"
    value = "go"
  }
  option {
    icon  = "/icon/rust.svg"
    name  = "Rust"
    value = "rust"
  }
  # option {
  #   icon  = "/icon/docker-white.svg"
  #   name  = "Docker"
  #   value = "docker"
  # }
  option {
    icon  = "/icon/widgets.svg"
    name  = "Embedded Development"
    value = "embedded"
  }
  option {
    icon  = "/icon/container.svg"
    name  = "Basic"
    value = "base"
  }
}

# module "dotfiles" {
#   source   = "registry.coder.com/modules/dotfiles/coder"
#   version  = "1.0.15"
#   agent_id = coder_agent.main.id
# }

# module "dotfiles-root" {
#   source       = "registry.coder.com/modules/dotfiles/coder"
#   version      = "1.0.15"
#   agent_id     = coder_agent.main.id
#   user         = "root"
#   dotfiles_uri = module.dotfiles.dotfiles_uri
# }

module "personalize" {
  source   = "registry.coder.com/modules/personalize/coder"
  version  = "1.0.2"
  agent_id = coder_agent.main.id
}

module "git-config" {
  source                = "registry.coder.com/modules/git-config/coder"
  version               = "1.0.15"
  agent_id              = coder_agent.main.id
  allow_username_change = true
  allow_email_change    = true
}

module "jetbrains_gateway" {
  source         = "registry.coder.com/modules/jetbrains-gateway/coder"
  version        = "1.0.13"
  agent_id       = coder_agent.main.id
  agent_name     = "example"
  folder         = "/home/coder/example"
  jetbrains_ides = ["IU", "PY", "WS", "CL", "GO", "PS", "RM", "RD"]
  default        = "IU"
  order          = 5
}

# module "vscode-web" {
#   source         = "registry.coder.com/modules/vscode-web/coder"
#   version        = "1.0.14"
#   agent_id       = coder_agent.main.id
#   folder         = "/workspace/${module.git_clone.folder_name}"
#   accept_license = true
#   order          = 4
# }

# resource "coder_app" "code-server" {
#   agent_id     = coder_agent.main.id
#   display_name = "VSCode Web"
#   slug         = "code-server"
#   url          = "http://localhost:13337/?folder=/workspace/${module.git_clone.folder_name}"
#   icon         = "/icon/code.svg"
#   subdomain    = false
#   share        = "owner"
# }

module "dotfiles-after-vscode-web" {
  source         = "katorlys-samples/dotfiles-after-vscode-web/coder"
  version        = "0.1.0"
  agent_id       = coder_agent.main.id
  folder         = "/workspace/${module.git_clone.folder_name}"
  accept_license = true
  order          = 4
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

data "docker_registry_image" "node" {
  count = data.coder_parameter.docker_image.value == "node" ? 1 : 0
  name  = "katorly/workspace-node:latest"
}

data "docker_registry_image" "python" {
  count = data.coder_parameter.docker_image.value == "python" ? 1 : 0
  name  = "katorly/workspace-python:latest"
}

data "docker_registry_image" "java" {
  count = data.coder_parameter.docker_image.value == "java" ? 1 : 0
  name  = "katorly/workspace-java:latest"
}

data "docker_registry_image" "c" {
  count = data.coder_parameter.docker_image.value == "c" ? 1 : 0
  name  = "katorly/workspace-c:latest"
}

data "docker_registry_image" "go" {
  count = data.coder_parameter.docker_image.value == "go" ? 1 : 0
  name  = "katorly/workspace-go:latest"
}

data "docker_registry_image" "rust" {
  count = data.coder_parameter.docker_image.value == "rust" ? 1 : 0
  name  = "katorly/workspace-rust:latest"
}

# data "docker_registry_image" "docker" {
#   count = data.coder_parameter.docker_image.value == "docker" ? 1 : 0
#   name  = "katorly/workspace-docker:latest"
# }

data "docker_registry_image" "embedded" {
  count = data.coder_parameter.docker_image.value == "embedded" ? 1 : 0
  name  = "katorly/workspace-embedded:latest"
}

data "docker_registry_image" "base" {
  count = data.coder_parameter.docker_image.value == "base" ? 1 : 0
  name  = "katorly/workspace-base:latest"
}

resource "docker_image" "node" {
  count         = data.coder_parameter.docker_image.value == "node" ? 1 : 0
  name          = data.docker_registry_image.node[0].name
  pull_triggers = [data.docker_registry_image.node[0].sha256_digest]
}

resource "docker_image" "python" {
  count         = data.coder_parameter.docker_image.value == "python" ? 1 : 0
  name          = data.docker_registry_image.python[0].name
  pull_triggers = [data.docker_registry_image.python[0].sha256_digest]
}

resource "docker_image" "java" {
  count         = data.coder_parameter.docker_image.value == "java" ? 1 : 0
  name          = data.docker_registry_image.java[0].name
  pull_triggers = [data.docker_registry_image.java[0].sha256_digest]
}

resource "docker_image" "c" {
  count         = data.coder_parameter.docker_image.value == "c" ? 1 : 0
  name          = data.docker_registry_image.c[0].name
  pull_triggers = [data.docker_registry_image.c[0].sha256_digest]
}

resource "docker_image" "go" {
  count         = data.coder_parameter.docker_image.value == "go" ? 1 : 0
  name          = data.docker_registry_image.go[0].name
  pull_triggers = [data.docker_registry_image.go[0].sha256_digest]
}

resource "docker_image" "rust" {
  count         = data.coder_parameter.docker_image.value == "rust" ? 1 : 0
  name          = data.docker_registry_image.rust[0].name
  pull_triggers = [data.docker_registry_image.rust[0].sha256_digest]
}

# resource "docker_image" "docker" {
#   count         = data.coder_parameter.docker_image.value == "docker" ? 1 : 0
#   name          = data.docker_registry_image.docker[0].name
#   pull_triggers = [data.docker_registry_image.docker[0].sha256_digest]
# }

resource "docker_image" "embedded" {
  count         = data.coder_parameter.docker_image.value == "embedded" ? 1 : 0
  name          = data.docker_registry_image.embedded[0].name
  pull_triggers = [data.docker_registry_image.embedded[0].sha256_digest]
}

resource "docker_image" "base" {
  count         = data.coder_parameter.docker_image.value == "base" ? 1 : 0
  name          = data.docker_registry_image.base[0].name
  pull_triggers = [data.docker_registry_image.base[0].sha256_digest]
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = local.images[data.coder_parameter.docker_image.value][0].image_id
  # Uses lower() to avoid Docker restriction on container names.
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: coder@my-workspace:~$
  hostname = data.coder_workspace.me.name
  # Use Cloudflare DNS
  dns = ["1.1.1.1"]
  # Use the docker gateway if the access URL is 127.0.0.1
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "EXTENSIONS_GALLERY={\"serviceUrl\":\"https://marketplace.visualstudio.com/_apis/public/gallery\",\"cacheUrl\":\"https://vscode.blob.core.windows.net/gallery/index\",\"itemUrl\":\"https://marketplace.visualstudio.com/items\",\"controlUrl\":\"\",\"recommendationsUrl\":\"\"}"
  ]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/workspace"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}
