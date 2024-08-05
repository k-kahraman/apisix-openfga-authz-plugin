-- Set test environment flag
_G._TEST_ENV = true

-- Mock JSON module
local json_mock = {
    encode = function(v)
        if type(v) == "string" then
            return '"' .. v .. '"'
        elseif type(v) == "table" then
            local parts = {}
            for k, v in pairs(v) do
                table.insert(parts, '"' .. tostring(k) .. '":' .. json_mock.encode(v))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        else
            return tostring(v)
        end
    end,
    decode = function(s)
        if s == '{"allowed": true}' then
            return { allowed = true }
        elseif s == '{"allowed": false}' then
            return { allowed = false }
        else
            return {}
        end
    end
}

-- Mock APISIX core module
local core_mock = {
    log = {
        error = function() end,
        info = function() end
    },
    request = {
        header = function(_, name)
            if name == "X-User-ID" then
                return "test-user"
            elseif name == "X-Custom-Relation" then
                return nil
            end
        end,
        get_uri_args = function() return {} end
    },
    schema = {
        check = function() return true end
    },
    json = json_mock,
    lrucache = {
        new = function()
            return function()
                return true
            end
        end
    }
}
package.loaded["apisix.core"] = core_mock

-- Mock HTTP module
local http_mock = {
    new = function()
        return {
            request_uri = function(_, url, opts)
                if url:match("check") then
                    return {
                        status = 200,
                        body = '{"allowed": true}'
                    }, nil
                end
                return nil, "mock error"
            end,
            set_timeout = function() end
        }
    end
}
package.loaded["resty.http"] = http_mock

-- Mock ngx shared dict
local shared_dict_mock = {
    get = function() return nil end,
    set = function() return true end
}
ngx = {
    shared = {
        openfga_config = shared_dict_mock
    },
    re = {
        match = function(subject, regex)
            return subject:match(regex)
        end
    }
}

-- Require the main plugin
local plugin = require('plugin.openfga_authz')

-- Test cases

-- 1. Schema Validation Tests
local function test_check_schema()
    -- Valid configuration
    local valid_conf = {
        openfga_url = "http://openfga:8080",
        store_id = "test-store",
        authorization_model_id = "test-model",
        resource_mappings = {
            {
                uri_pattern = "/api/v1/documents/.*",
                resource_type = "document",
                id_location = "last_part"
            }
        }
    }
    assert(plugin.check_schema(valid_conf), "Valid configuration should pass schema check")

    -- Invalid configuration: missing required fields
    local invalid_conf1 = {
        openfga_url = "http://openfga:8080"
    }
    assert(not plugin.check_schema(invalid_conf1), "Configuration missing required fields should fail")

    -- Invalid configuration: invalid resource mapping
    local invalid_conf2 = {
        openfga_url = "http://openfga:8080",
        store_id = "test-store",
        authorization_model_id = "test-model",
        resource_mappings = {
            {
                uri_pattern = "/api/v1/documents/.*",
                resource_type = "document",
                id_location = "invalid_location"
            }
        }
    }
    assert(not plugin.check_schema(invalid_conf2), "Configuration with invalid id_location should fail")
end

-- 2. Resource Info Extraction Tests
local function test_get_resource_info()
    local conf = {
        resource_mappings = {
            {
                uri_pattern = "/api/v1/documents/.*",
                resource_type = "document",
                id_location = "last_part"
            },
            {
                uri_pattern = "/api/v2/files/.*",
                resource_type = "file",
                id_location = "query_param",
                id_key = "file_id"
            },
            {
                uri_pattern = "/api/v3/users/.*",
                resource_type = "user",
                id_location = "header",
                id_key = "X-User-ID"
            }
        }
    }

    -- Test last_part extraction
    local resource_type, resource_id = plugin.get_resource_info("/api/v1/documents/123", "GET", conf, {})
    assert(resource_type == "document" and resource_id == "123", "Failed to extract last_part resource info")

    -- Test query_param extraction
    local ctx = { var = {} }
    core_mock.request.get_uri_args = function() return { file_id = "456" } end
    resource_type, resource_id = plugin.get_resource_info("/api/v2/files/get", "GET", conf, ctx)
    assert(resource_type == "file" and resource_id == "456", "Failed to extract query_param resource info")

    -- Test header extraction
    core_mock.request.header = function(_, name)
        if name == "X-User-ID" then return "789" end
        return nil
    end
    resource_type, resource_id = plugin.get_resource_info("/api/v3/users/profile", "GET", conf, {})
    assert(resource_type == "user" and resource_id == "789", "Failed to extract header resource info")

    -- Test non-matching URI
    resource_type, resource_id = plugin.get_resource_info("/api/v4/unknown/resource", "GET", conf, {})
    assert(resource_type == nil and resource_id == nil, "Non-matching URI should return nil values")
end

-- 3. Relation Mapping Tests
local function test_get_relation()
    local conf = {
        relation_mappings = {
            GET = "reader",
            POST = "writer",
            PUT = "writer",
            DELETE = "admin"
        },
        use_dynamic_config = true
    }

    -- Test static mappings
    assert(plugin.get_relation("GET", "document", conf, {}) == "reader", "Failed to get correct GET relation")
    assert(plugin.get_relation("POST", "document", conf, {}) == "writer", "Failed to get correct POST relation")
    assert(plugin.get_relation("DELETE", "document", conf, {}) == "admin", "Failed to get correct DELETE relation")

    -- Test custom header override
    core_mock.request.header = function(_, name)
        if name == "X-Custom-Relation" then return "custom_relation" end
        return nil
    end
    assert(plugin.get_relation("GET", "document", conf, {}) == "custom_relation",
        "Failed to apply custom relation header")

    -- Test dynamic configuration
    local dynamic_mappings = { PUT = "editor", PATCH = "editor" }
    shared_dict_mock.get = function(_, key)
        if key == "relation_mappings" then
            return core_mock.json.encode(dynamic_mappings)
        end
        return nil
    end
    assert(plugin.get_relation("PUT", "document", conf, {}) == "editor", "Failed to get relation from dynamic config")
    assert(plugin.get_relation("PATCH", "document", conf, {}) == "editor", "Failed to get relation from dynamic config")

    -- Test fallback to default
    assert(plugin.get_relation("OPTIONS", "document", conf, {}) == "can_access", "Failed to fallback to default relation")
end

-- 4. Access Control Tests
local function test_access()
    local conf = {
        openfga_url = "http://openfga:8080",
        store_id = "test-store",
        authorization_model_id = "test-model",
        resource_mappings = {
            {
                uri_pattern = "/api/v1/documents/.*",
                resource_type = "document",
                id_location = "last_part"
            }
        },
        relation_mappings = {
            GET = "reader"
        }
    }

    -- Test allowed access
    local ctx = {
        var = {
            uri = "/api/v1/documents/123",
            request_method = "GET"
        }
    }
    core_mock.request.header = function(_, name)
        if name == "X-User-ID" then return "test-user" end
        return nil
    end
    http_mock.new = function()
        return {
            request_uri = function(_, url, opts)
                if url:match("check") then
                    return {
                        status = 200,
                        body = '{"allowed": true}'
                    }, nil
                end
                return nil, "mock error"
            end,
            set_timeout = function() end
        }
    end
    local code, body = plugin.access(conf, ctx)
    assert(code == nil and body == nil, "Access should be allowed")

    -- Test denied access
    http_mock.new = function()
        return {
            request_uri = function(_, url, opts)
                if url:match("check") then
                    return {
                        status = 200,
                        body = '{"allowed": false}'
                    }, nil
                end
                return nil, "mock error"
            end,
            set_timeout = function() end
        }
    end
    code, body = plugin.access(conf, ctx)
    assert(code == 403 and body.message == "Access denied", "Access should be denied")

    -- Test missing user ID
    core_mock.request.header = function(_, name) return nil end
    code, body = plugin.access(conf, ctx)
    assert(code == 401 and body.message == "User ID not provided", "Should return 401 when user ID is missing")

    -- Test OpenFGA error
    http_mock.new = function()
        return {
            request_uri = function(_, url, opts)
                return nil, "OpenFGA error"
            end,
            set_timeout = function() end
        }
    end
    code, body = plugin.access(conf, ctx)
    assert(code == 500 and body.message == "Internal server error", "Should return 500 on OpenFGA error")
end

-- 5. Dynamic Configuration Update Test
local function test_update_dynamic_config()
    local new_config = {
        relation_mappings = {
            GET = "viewer",
            POST = "editor"
        }
    }

    -- Mock the API call
    local api_handler = plugin.api()[1].handler
    local ctx = {
        var = {
            request_body = core_mock.json.encode(new_config)
        }
    }

    local code, response = api_handler({}, ctx)
    assert(code == 200, "Dynamic configuration update should succeed")
    assert(response.message == "Configuration updated successfully", "Update should return success message")

    -- Verify the update was applied
    local stored_config = core_mock.json.decode(shared_dict_mock.get(nil, "relation_mappings"))
    assert(deep_compare(stored_config, new_config.relation_mappings), "Stored configuration should match the update")
end

-- Run all tests
local function run_tests()
    local tests = {
        test_check_schema,
        test_get_resource_info,
        test_get_relation,
        test_access,
        test_update_dynamic_config
    }

    for i, test in ipairs(tests) do
        local status, error = pcall(test)
        if status then
            print(string.format("Test %d passed", i))
        else
            print(string.format("Test %d failed: %s", i, error))
        end
    end
end

run_tests()
