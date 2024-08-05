# OpenFGA Authorization Plugin for Apache APISIX

This plugin integrates [OpenFGA](https://openfga.dev/) (Fine-Grained Authorization) with [Apache APISIX](https://apisix.apache.org/), allowing you to implement fine-grained authorization checks in your API gateway.

## Features

- Seamless integration of OpenFGA authorization with Apache APISIX
- Flexible resource and relation mapping
- Support for multiple OpenFGA stores and authorization models
- Dynamic configuration updates without APISIX restarts
- Caching for improved performance
- Detailed logging and error handling
- Prometheus metrics for monitoring

## Installation

1. Clone this repository into the `apisix/plugins` directory of your Apache APISIX installation:

   ```
   git clone https://github.com/k-kahraman/apisix-openfga-authz-plugin.git /path/to/apisix/plugins/openfga_authz
   ```

2. Add the plugin name to your APISIX configuration file (`config.yaml`):

   ```yaml
   plugins:
     - ... # other plugins
     - openfga_authz
   ```

3. Restart Apache APISIX.

## Configuration

Here's an example configuration for the plugin:

```yaml
plugins:
  openfga_authz:
    openfga_config:
      - url: "https://your-openfga-instance.com"
        store_id: "your-store-id"
        authorization_model_id: "your-model-id"
    resource_mappings:
      - uri_pattern: "/api/v1/documents/.*"
        resource_type: "document"
        id_location: "last_part"
    relation_mappings:
      GET: "reader"
      POST: "writer"
      PUT: "writer"
      DELETE: "admin"
    use_dynamic_config: true
    cache_ttl: 300
```

For detailed configuration options, please refer to the [Configuration Guide](docs/configuration.md).

## Usage

Once configured, the plugin will automatically check permissions for incoming requests against your OpenFGA store. For example:

```
curl -H "X-User-ID: user:alice" http://your-apisix-instance/api/v1/documents/123
```

This request will be allowed only if the user "alice" has "reader" access to the document with ID "123" in your OpenFGA store.

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details on how to submit pull requests, report issues, or request features.

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](LICENSE) file for details.

## Support

For questions, feature requests, or bug reports, please open an issue on our GitHub repository. For further assist feel free to contact me at kaan@kahraman.io
