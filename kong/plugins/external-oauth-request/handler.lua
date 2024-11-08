local http = require "resty.http"
local cjson = require "cjson"
local kong = kong

local ExternalAuthHandler = {
  VERSION  = "2.0.0",
}

local CACHE_TOKEN_KEY = "oauth_token"
local EXPIRATION_MARGIN = 5

local priority_env_var = "EXTERNAL_OAUTH_REQUEST_PRIORITY"
local priority
if os.getenv(priority_env_var) then
  priority = tonumber(os.getenv(priority_env_var))
else
  priority = 900
end
kong.log.debug('EXTERNAL_OAUTH_REQUEST_PRIORITY: ' .. priority)

ExternalAuthHandler.PRIORITY = priority

-----------
-- ACCESS
-----------
function ExternalAuthHandler:access(conf)

  local tokenInfo = nil

  -- Get token with cache
  if conf.cache_enabled then
    if conf.log_enabled then
      kong.log.info("Cache enabled")
    end
    tokenInfo = get_cache_token(conf)
    if not tokenInfo then
      if conf.log_enabled then
        kong.log.info("No token in cache. Call OAuth provider to update it")
      end
      tokenInfo = kong.cache:get(CACHE_TOKEN_KEY .. "_" .. conf.token_url .. "_" .. conf.client_id, nil, get_oauth_token, conf)
    end
    -- Get token without cache
  else
    tokenInfo = get_oauth_token(conf)
  end

  -- Final validation and set header
  if not tokenInfo then
    return kong.response.exit(401, {
      message = "Invalid authentication credentials"
    })
  end

  if conf.log_enabled then
    kong.log.info("Login success.")
    kong.log.debug("Token: " .. cjson.encode(tokenInfo))
  end

  kong.service.request.set_header(conf.header_request, "Bearer " .. tokenInfo.token)
end

-----------
-- RESPONSE
-----------
function ExternalAuthHandler:response(conf)

  if conf.cache_enabled and (kong.response.get_status() == 401) then
    if conf.log_enabled then
      kong.log.info("Unauthorized response. Invalidate token from cache")
    end

    kong.cache:invalidate(CACHE_TOKEN_KEY .. "_" .. conf.token_url .. "_" .. conf.client_id)
  end
end

-------------
-- FUNCTIONS
-------------

-- Get token from cache
function get_cache_token(conf)
  local token = kong.cache:get(CACHE_TOKEN_KEY .. "_" .. conf.token_url .. "_" .. conf.client_id)
  -- If value in cache is nil we must invalidate it
  if not token then
    kong.cache:invalidate(CACHE_TOKEN_KEY .. "_" .. conf.token_url .. "_" .. conf.client_id)
    return nil
  end

  if token.expiration and (token.expiration < os.time()) then
    -- Token is expired invalidate it
    if conf.log_enabled then
      kong.log.debug("Invalidate expired token: " .. cjson.encode(token))
    end
    kong.cache:invalidate(CACHE_TOKEN_KEY .. "_" .. conf.token_url .. "_" .. conf.client_id)
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
    kong.log.info("Login via external OAuth")
    kong.log.debug("Token URL:  ", conf.token_url)
    kong.log.debug("Grant type: ", conf.grant_type)
  end

  local request_body = "grant_type=" .. conf.grant_type .. "&client_id=" .. conf.client_id .. "&client_secret=" ..
                         conf.client_secret

  if conf.grant_type == "password" then
    request_body = request_body .. "&username=" .. conf.username .. "&password=" .. conf.password
  end

  local client = http.new()
  client:set_timeouts(conf.connect_timeout, conf.send_timeout, conf.read_timeout)

  return client:request_uri(conf.token_url, {
    method = "POST",
    ssl_verify = conf.ssl_verify_enabled,
    body = request_body,
    headers = {
      ["Content-Type"] = "application/x-www-form-urlencoded"
    }
  })
end

-- Validate login response
function validate_login(res, err, conf)
  if not res then
    if conf.log_enabled then
      kong.log.err("No response. Error: ", err)
    end
    return "No response from OAuth provider"
  end

  if res.status ~= 200 then
    if conf.log_enabled then
      kong.log.err("Got error status ", res.status, res.body)
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
    kong.log.debug("Current time: ", os.time())
    kong.log.debug("Expiration time: ", expiration)
  end

  return {
    token = responseBody.access_token,
    ttl = responseBody.expires_in,
    expiration = expiration
  };
end

return ExternalAuthHandler
