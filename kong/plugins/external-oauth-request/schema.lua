local typedefs = require "kong.db.schema.typedefs"

return {
  name = "external-oauth-request",
  fields = {
    {
      consumer = typedefs.no_consumer
    },
    {
      config = {
        type = "record",
        fields = {
          token_url = {
            required = true,
            type = "url"
          },
          grant_type = {
            default = "client_credentials",
            type = "string"
          },
          client_id = {
            required = true,
            type = "string"
          },
          client_secret = {
            required = true,
            type = "string"
          },
          header_request = {
            default = "Authorization",
            type = "string"
          },
          connect_timeout = {
            default = 10000,
            type = "number"
          },
          send_timeout = {
            default = 60000,
            type = "number"
          },
          read_timeout = {
            default = 60000,
            type = "number"
          },
          ssl_verify_enabled = {
            default = false,
            type = "boolean"
          },
          cache_enabled = {
            default = false,
            type = "boolean"
          },
          log_enabled = {
            default = false,
            type = "boolean"
          }
        }
      }
    }
  }
}
