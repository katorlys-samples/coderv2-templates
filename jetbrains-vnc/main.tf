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
  image_map = {
    java     = "katorly/vnc-intellij-c:latest"
    python   = "katorly/vnc-pycharm-c:latest"
    node     = "katorly/vnc-webstorm:latest"
    rust     = "katorly/vnc-rustrover:latest"
  }
}

provider "docker" {}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<-EOT
    set -e
    
    # Start JetBrains IDE in the background.
    nohup dbus-launch --exit-with-session /process_monitor.sh > /dev/null 2>&1 &
  EOT
  
  # These environment variables allow you to make Git commits right away after creating a
  # workspace. Note that they take precedence over configuration defined in ~/.gitconfig!
  # You can remove this block if you'd prefer to configure Git manually or using
  # dotfiles. (see docs/dotfiles.md)
  # env = {
  #   GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  #   GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
  #   GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  #   GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
  # }
}

data "coder_parameter" "git_repo" {
  name         = "git_repo"
  display_name = "Git repository"
  default      = "https://github.com/katorlys-samples/Template"
}

module "git_clone" {
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  url      = data.coder_parameter.git_repo.value
  base_dir = "/workspace"
}

data "coder_external_auth" "github" {
  id = "github"
}

data "coder_parameter" "docker_image" {
  icon        = "/icon/projector.svg"
  name        = "JetBrains IDE"
  description = "Which JetBrains IDE do you want to use?"
  type        = "string"
  default     = "java"
  mutable     = true

  option {
    icon  = "/icon/intellij.svg"
    name  = "IntelliJ IDEA Community"
    value = "java"
  }
  option {
    icon  = "/icon/pycharm.svg"
    name  = "PyCharm Community"
    value = "python"
  }
  option {
    icon  = "/icon/webstorm.svg"
    name  = "WebStorm"
    value = "node"
  }
  option {
    icon  = "/icon/rustrover.svg"
    name  = "RustRover"
    value = "rust"
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
  source   = "registry.coder.com/coder/personalize/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
}

# module "git-config" {
#   source                = "registry.coder.com/modules/git-config/coder"
#   version               = "1.0.15"
#   agent_id              = coder_agent.main.id
#   allow_username_change = true
#   allow_email_change    = true
# }

resource "coder_app" "novnc" {
  agent_id      = coder_agent.main.id
  slug          = "novnc"
  display_name  = "JetBrains IDE in noVNC"
  icon          = "/icon/projector.svg"
  url           = "http://localhost:6081"
  subdomain     = false
  share         = "owner"
  order         = 4
}

# module "vscode-web" {
#   source         = "registry.coder.com/modules/vscode-web/coder"
#   version        = "1.0.14"
#   agent_id       = coder_agent.main.id
#   folder         = "/workspace/${module.git_clone.folder_name}"
#   accept_license = true
#   order          = 5
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

module "dotfiles-after-code-server" {
  count          = data.coder_workspace.me.start_count
  source         = "katorlys-samples/dotfiles-after-code-server/coder"
  version        = "~> 0.1"
  agent_id       = coder_agent.main.id
  folder         = "/workspace/${module.git_clone.folder_name}"
  subdomain      = false
  share          = "owner"
  default_dotfiles_uri = "https://github.com/katorly/dotfiles"
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

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = local.image_map[data.coder_parameter.docker_image.value]
  # Uses lower() to avoid Docker restriction on container names.
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: coder@my-workspace:~$
  hostname = data.coder_workspace.me.name
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
