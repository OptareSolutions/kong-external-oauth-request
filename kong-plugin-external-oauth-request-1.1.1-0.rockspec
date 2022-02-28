local plugin_name = "external-oauth-request"
local package_name = "kong-plugin-" .. plugin_name
local package_version = "1.1.1"
local rockspec_revision = "0"

local github_account_name = "OptareSolutions"
local github_repo_name = "kong-external-oauth-request"
local github_tag = "main"

package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }
source = {
    url = "git://github.com/"..github_account_name.."/"..github_repo_name,
    tag = github_tag,
    dir = github_repo_name
}

description = {
  summary = "A Kong plugin for performing authentication to and endpoint by getting OAuth token from a remote provider and injecting the received token in the Bearer header",
  homepage = "https://github.com/"..github_account_name.."/"..github_repo_name,
  license = "Apache 2.0",
}

dependencies = {
}

build = {
  type = "builtin",
  modules = {
    -- TODO: add any additional code files added to the plugin
    ["kong.plugins."..plugin_name..".handler"] = "kong/plugins/"..plugin_name.."/handler.lua",
    ["kong.plugins."..plugin_name..".schema"] = "kong/plugins/"..plugin_name.."/schema.lua",
  }
}
