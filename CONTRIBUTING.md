# Contributing to SDN Automation

Thank you for your interest in contributing to SDN Automation! This document provides guidelines and instructions for contributing.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Create a virtual environment and install dependencies:
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   pip install -r requirements.txt
   ```

## Development Workflow

1. Create a new branch for your feature or bugfix:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes following the code style guidelines

3. Add or update tests as needed

4. Run the test suite:
   ```bash
   python -m unittest discover tests -v
   ```

5. Commit your changes with a clear message:
   ```bash
   git commit -m "Add feature: description of your changes"
   ```

6. Push to your fork and submit a pull request

## Code Style Guidelines

- Follow PEP 8 style guide
- Use meaningful variable and function names
- Add docstrings to all public functions, classes, and modules
- Use type hints where appropriate
- Keep functions focused and small
- Write self-documenting code with clear logic

### Example Code Style

```python
def provision_network(self, network: str, comment: str = '') -> bool:
    """
    Provision a new network.
    
    Args:
        network: Network CIDR (e.g., '10.0.0.0/24')
        comment: Optional comment for the network
        
    Returns:
        True if successful, False otherwise
    """
    # Implementation
    pass
```

## Testing Guidelines

- Write unit tests for all new functionality
- Ensure tests are isolated and don't depend on external services
- Use mocks for external API calls
- Aim for high test coverage
- Test both success and failure scenarios

### Example Test

```python
def test_provision_network_success(self):
    """Test successful network provisioning."""
    # Setup mocks
    self.mock_client.get_network.return_value = None
    self.mock_client.create_network.return_value = {'_ref': 'network/abc123'}
    
    # Test
    result = self.manager.provision_network('10.0.0.0/24', 'Test Network')
    
    # Assertions
    self.assertTrue(result)
```

## Documentation

- Update README.md if you add new features
- Add docstrings to all public APIs
- Create examples for significant new features
- Update the API reference section if needed

## Pull Request Process

1. Ensure all tests pass
2. Update documentation as needed
3. Add a clear description of your changes
4. Link any related issues
5. Request review from maintainers

## Reporting Issues

When reporting issues, please include:

- Clear description of the problem
- Steps to reproduce
- Expected behavior
- Actual behavior
- Environment details (Python version, OS, etc.)
- Relevant logs or error messages

## Feature Requests

We welcome feature requests! Please:

- Check if the feature already exists or is planned
- Provide a clear use case
- Explain how it would benefit users
- Be open to discussion about implementation

## Code of Conduct

- Be respectful and inclusive
- Welcome newcomers
- Focus on constructive feedback
- Collaborate openly

## Questions?

Feel free to open an issue for questions or reach out to the maintainers.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
