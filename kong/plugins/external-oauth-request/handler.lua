local BasePlugin = require "kong.plugins.base_plugin"
local http = require "resty.http"
local cjson = require "cjson"
local kong = kong
local ExternalAuthHandler = BasePlugin:extend()

local CACHE_TOKEN_KEY = "oauth_token"
local EXPIRATION_MARGIN = 5

function ExternalAuthHandler:new()
  ExternalAuthHandler.super.new(self, "external-oauth-request")
end


-----------
-- ACCESS
-----------
function ExternalAuthHandler:access(conf)
  ExternalAuthHandler.super.access(self)

  local tokenInfo = nil

  -- Get token with cache
  if conf.cache_enabled then
    if conf.log_enabled then
      kong.log.warn("Cache enabled")
    end
    tokenInfo = get_cache_token(conf)
    if not tokenInfo then
      if conf.log_enabled then
        kong.log.warn("No token in cache. Call OAuth provider to update it")
      end
      tokenInfo = kong.cache:get(CACHE_TOKEN_KEY, nil, get_oauth_token, conf)
    end
  -- Get token without cache
  else
    tokenInfo = get_oauth_token(conf)
  end

  -- Final validation and set header
  if not tokenInfo then
    return kong.response.exit(401, {message="Invalid authentication credentials"})
  end

  if conf.log_enabled then
    kong.log.warn("Login success. Token: " .. cjson.encode(tokenInfo))
  end

  kong.service.request.set_header(conf.header_request, "Bearer " .. tokenInfo.token)
end


-----------
-- RESPONSE
-----------
function ExternalAuthHandler:response(conf)
  ExternalAuthHandler.super.response(self)

  if conf.cache_enabled and (kong.response.get_status() == 401) then
    if conf.log_enabled then
      kong.log.warn("Unauthorized response. Invalidate token from cache")
    end

    kong.cache:invalidate(CACHE_TOKEN_KEY)
  end  
end


-------------
-- FUNCTIONS
-------------

-- Get token from cache
function get_cache_token(conf)
  local token = kong.cache:get(CACHE_TOKEN_KEY)
  -- If value in cache is nil we must invalidate it
  if not token then
    kong.cache:invalidate(CACHE_TOKEN_KEY)
    return nil
  end

  if token.expiration and (token.expiration < os.time()) then
    -- Token is expired invalidate it
    if conf.log_enabled then
      kong.log.warn("Invalidate expired token: " .. cjson.encode(token))
    end
    kong.cache:invalidate(CACHE_TOKEN_KEY)
    return nil
  end

  return token
end

-- Get token from OAuth provider
function get_oauth_token(conf)
  local res, err = perform_login(conf)

  local error_message = validate_login(res, err, conf)
  if error_message then
    return nil;
  end

  return get_token_from_response(res, conf)
end

-- Login
function perform_login(conf)
  if conf.log_enabled then
    kong.log.warn("Login via external OAuth")
    kong.log.warn("Token URL:  ", conf.token_url)
    kong.log.warn("Grant type: ", conf.grant_type)
  end

  local request_body = "grant_type=" .. conf.grant_type .. "&client_id=" .. conf.client_id .. "&client_secret=" .. conf.client_secret

  if conf.grant_type == "password" then
    request_body = request_body .. "&username=" .. conf.username .. "&password=" .. conf.password
  end

  local client = http.new()
  client:set_timeouts(conf.connect_timeout, conf.send_timeout, conf.read_timeout)

  return client:request_uri(
    conf.token_url, 
    {
      method = "POST",
      ssl_verify = conf.ssl_verify_enabled,
      body = request_body,
      headers = {
        ["Content-Type"] = "application/x-www-form-urlencoded"
      }
    }
  )
end


-- Validate login response
function validate_login(res, err, conf)
  if not res then
    if conf.log_enabled then
      kong.log.warn("No response. Error: ", err)
    end
    return "No response from OAuth provider"
  end

  if res.status ~= 200 then
    if conf.log_enabled then
      kong.log.warn("Got error status ", res.status, res.body)
    end
    return "Invalid authentication credentials"
  end
end


-- Extract token
function get_token_from_response(res, conf)
  local responseBody = cjson.decode(res.body)
  local token = responseBody.access_token

  local expiration = nil
  if responseBody.expires_in then
    expiration = os.time() + responseBody.expires_in - EXPIRATION_MARGIN
  end

  if conf.log_enabled then
    kong.log.warn("Current time: ", os.time())
    kong.log.warn("Expiration time: ", expiration)
  end

  return {
    token = responseBody.access_token,
    ttl = responseBody.expires_in,
    expiration = expiration
  };
end

ExternalAuthHandler.PRIORITY = 900
ExternalAuthHandler.VERSION = "1.0.0"

return ExternalAuthHandler