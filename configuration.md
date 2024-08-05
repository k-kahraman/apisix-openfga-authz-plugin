# APISIX OpenFGA Authorization Plugin Configuration Guide

This document provides a detailed explanation of all configuration options for the APISIX OpenFGA Authorization Plugin for Apache APISIX.

## Plugin Configuration

The plugin is configured as part of your APISIX route or global configuration. Here's a comprehensive example:

```yaml
plugins:
  openfga_authz:
    openfga_config:
      - url: "https://your-openfga-instance.com"
        store_id: "your-store-id"
        authorization_model_id: "your-model-id"
        client_id: "your-client-id"
        client_secret: "your-client-secret"
    resource_mappings: # These can be set dynamically via API calls
      - uri_pattern: "/api/v1/documents/.*"
        resource_type: "document"
        id_location: "last_part"
      - uri_pattern: "/api/v1/projects/(.*)/tasks/.*"
        resource_type: "task"
        id_location: "query_param"
        id_key: "task_id"
    relation_mappings:
      GET: "reader"
      POST: "writer"
      PUT: "writer"
      DELETE: "admin"
    use_dynamic_config: true
    cache_ttl: 300
    https: true
    timeout: 5000
    keepalive: true
    keepalive_timeout: 60000
    keepalive_pool: 5
```

### OpenFGA Configuration (`openfga_config`)

- `url` (string, required): The URL of your OpenFGA instance.
- `store_id` (string, required): The ID of your OpenFGA store.
- `authorization_model_id` (string, required): The ID of your authorization model in OpenFGA.
- `client_id` (string, optional): Your client ID for authenticating with OpenFGA.
- `client_secret` (string, optional): Your client secret for authenticating with OpenFGA.

You can configure multiple OpenFGA instances by adding more items to the `openfga_config` array.

### Resource Mappings (`resource_mappings`)

This section defines how to map incoming requests to OpenFGA resources.

- `uri_pattern` (string, required): A regular expression pattern to match against the request URI.
- `resource_type` (string, required): The type of resource in your OpenFGA model.
- `id_location` (string, required): Where to find the resource ID. Options are:
  - `last_part`: The last part of the URI path.
  - `query_param`: A query parameter in the URI.
  - `header`: A request header.
  - `body`: In the request body (for POST/PUT requests).
- `id_key` (string, required for `query_param`, `header`, and `body`): The name of the parameter, header, or body field containing the resource ID.

### Relation Mappings (`relation_mappings`)

This section maps HTTP methods to OpenFGA relations.

- Key: HTTP method (GET, POST, PUT, DELETE, etc.)
- Value: Corresponding OpenFGA relation (e.g., reader, writer, admin)

### Other Options

- `use_dynamic_config` (boolean, default: false): If true, allows runtime updates to the configuration.
- `cache_ttl` (integer, default: 300): Time-to-live for cached authorization decisions, in seconds.
- `https` (boolean, default: true): Use HTTPS for OpenFGA API calls.
- `timeout` (integer, default: 5000): Timeout for OpenFGA API calls, in milliseconds.
- `keepalive` (boolean, default: true): Use keepalive connections for OpenFGA API calls.
- `keepalive_timeout` (integer, default: 60000): Keepalive timeout, in milliseconds.
- `keepalive_pool` (integer, default: 5): Maximum number of idle keepalive connections.

## Dynamic Configuration

If `use_dynamic_config` is set to `true`, you can update the `relation_mappings` at runtime using the following API endpoint:

```
POST /apisix/plugin/openfga_authz/config
```

Request body:

```json
{
  "relation_mappings": {
    "GET": "viewer",
    "POST": "editor",
    "PUT": "editor",
    "DELETE": "admin"
  }
}
```

This allows you to change the relation mappings without restarting APISIX.

## Best Practices

1. Use HTTPS for secure communication with your OpenFGA instance.
2. Regularly rotate your client secrets.
3. Use specific `uri_pattern`s to avoid unnecessary authorization checks.
4. Set appropriate `cache_ttl` to balance between performance and freshness of authorization decisions.
5. Monitor the provided Prometheus metrics to track the plugin's performance and adjust configurations as needed. **WIP**
