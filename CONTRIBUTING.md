# Contributing to OpenFGA Authorization Plugin for Apache APISIX

We welcome contributions to the OpenFGA Authorization Plugin for Apache APISIX! This document outlines the process for contributing to this project.

## Getting Started

1. Fork the repository on GitHub.
2. Clone your fork locally:
   ```
   git clone https://github.com/k-kahraman/apisix-openfga-authz-plugin.git
   cd apisix-openfga-plugin
   ```

## Making Changes

1. Create a new branch for your changes:
   ```
   git checkout -b my-new-feature
   ```
2. Make your changes and test them thoroughly.
3. Commit your changes:
   ```
   git commit -am 'Add some feature'
   ```
4. Push to your fork:
   ```
   git push origin my-new-feature
   ```
5. Create a new Pull Request on GitHub.

## Coding Standards

- Follow the Lua style guide: https://github.com/Olivine-Labs/lua-style-guide
- Use 4 spaces for indentation.
- Add comments for complex logic.
- Update documentation if you're changing functionality.

## Testing

- Add unit tests for new functionality.
- Ensure all existing tests pass before submitting a pull request.

## Reporting Issues

- Use the GitHub issue tracker to report bugs.
- Describe the bug concisely and provide steps to reproduce it.
- Specify your environment (APISIX version, OpenFGA version, etc.).

## Feature Requests

- Use the GitHub issue tracker to suggest new features.
- Clearly describe the feature and its potential benefits.
