local core = require("apisix.core")
local http = require("resty.http")
local json = require("cjson")

local plugin_name = "openfga_authz"

-- Create a shared dictionary to store dynamic configuration
local config_dict = ngx.shared.openfga_config

local function update_dynamic_config(key, value)
    local ok, err = config_dict:set(key, json.encode(value))
    if not ok then
        core.log.error("Failed to update dynamic config: ", err)
    end
end

local function get_dynamic_config(key)
    local value, err = config_dict:get(key)
    if not value then
        return nil
    end
    return json.decode(value)
end

-- Enhanced schema to allow custom mapping and dynamic configuration
local schema = {
    type = "object",
    properties = {
        openfga_url = { type = "string" },
        store_id = { type = "string" },
        authorization_model_id = { type = "string" },
        resource_mappings = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    uri_pattern = { type = "string" },
                    resource_type = { type = "string" },
                    id_location = {
                        type = "string",
                        enum = { "last_part", "query_param", "header" }
                    },
                    id_key = { type = "string" },
                },
                required = { "uri_pattern", "resource_type", "id_location" },
            },
        },
        relation_mappings = {
            type = "object",
            patternProperties = {
                ["^[A-Z]+$"] = { type = "string" }
            },
        },
        use_dynamic_config = { type = "boolean", default = false },
    },
    required = { "openfga_url", "store_id", "authorization_model_id", "resource_mappings" },
}

local _M = {
    version = 0.1,
    priority = 2500,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

local lrucache = core.lrucache.new({
    ttl = 300,
    count = 10000,
})

function _M.get_resource_info(uri, method, conf, ctx)
    for _, mapping in ipairs(conf.resource_mappings) do
        -- Match using regex
        if ngx.re.match(uri, mapping.uri_pattern, "jo") then
            local resource_id
            if mapping.id_location == "last_part" then
                resource_id = uri:match("/([^/]+)$")
            elseif mapping.id_location == "query_param" then
                resource_id = core.request.get_uri_args(ctx)[mapping.id_key]
            elseif mapping.id_location == "header" then
                resource_id = core.request.header(ctx, mapping.id_key)
            end

            return mapping.resource_type, resource_id
        end
    end
    return nil, nil
end

function _M.get_relation(method, resource_type, conf, ctx)
    local relation

    -- Check for custom header override
    local custom_relation = core.request.header(ctx, "X-Custom-Relation")
    if custom_relation then
        return custom_relation
    end

    -- Use dynamic configuration if enabled
    if conf.use_dynamic_config then
        local dynamic_mappings = get_dynamic_config("relation_mappings")
        if dynamic_mappings then
            relation = dynamic_mappings[method]
        end
    end

    -- Fall back to static configuration if dynamic is not set
    if not relation then
        relation = conf.relation_mappings and conf.relation_mappings[method]
    end

    -- Default to "can_access" if no mapping found
    return relation or "can_access"
end

function _M.access(conf, ctx)
    local user_id = core.request.header(ctx, "X-User-ID")
    local uri = ctx.var.uri
    local method = ctx.var.request_method

    if not user_id then
        core.log.error("User ID not provided")
        return 401, { message = "User ID not provided" }
    end

    local resource_type, resource_id = _M.get_resource_info(uri, method, conf, ctx)
    local relation = _M.get_relation(method, resource_type, conf, ctx)

    if not resource_type or not resource_id then
        core.log.error("Unable to determine resource type or ID")
        return 500, { message = "Internal server error" }
    end

    local cache_key = user_id .. ":" .. resource_type .. ":" .. resource_id .. ":" .. relation

    local allowed, err = lrucache(cache_key, nil, function()
        local client = http.new()
        client:set_timeout(5000)

        local res, err = client:request_uri(conf.openfga_url .. "/stores/" .. conf.store_id .. "/check", {
            method = "POST",
            headers = {
                ["Content-Type"] = "application/json",
            },
            body = json.encode({
                tuple_key = {
                    user = "user:" .. user_id,
                    relation = relation,
                    object = resource_type .. ":" .. resource_id,
                },
                authorization_model_id = conf.authorization_model_id,
            }),
        })

        if not res then
            core.log.error("Failed to request OpenFGA: ", err)
            return nil, "Failed to request OpenFGA"
        end

        if res.status ~= 200 then
            core.log.error("OpenFGA returned non-200 status: ", res.status)
            return nil, "OpenFGA returned non-200 status"
        end

        local body = json.decode(res.body)
        return body.allowed
    end)

    if err then
        core.log.error("Authorization check failed: ", err)
        return 500, { message = "Internal server error" }
    end

    if not allowed then
        core.log.info("Access denied for user ", user_id, " to ", resource_type, ":", resource_id, " with relation ",
            relation)
        return 403, { message = "Access denied" }
    end

    core.log.info("Access granted for user ", user_id, " to ", resource_type, ":", resource_id, " with relation ",
        relation)
end

-- Add an API to update dynamic configuration
function _M.api()
    return {
        {
            methods = { "POST" },
            uri = "/apisix/plugin/openfga_authz/config",
            handler = function(conf, ctx)
                local req_body = core.request.get_body()
                local config = json.decode(req_body)
                update_dynamic_config("relation_mappings", config.relation_mappings)
                return 200, { message = "Configuration updated successfully" }
            end
        }
    }
end

return _M
