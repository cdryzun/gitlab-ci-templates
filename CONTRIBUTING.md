# Contributing to gitlab-ci-templates

Thank you for your interest in contributing to this project!

## How to Contribute

### Reporting Issues

If you find a bug or have a suggestion for improvement:

1. Check if the issue already exists in [GitHub Issues](https://github.com/cdryzun/gitlab-ci-templates/issues)
2. If not, create a new issue with:
   - Clear title and description
   - Steps to reproduce (for bugs)
   - Expected vs actual behavior
   - Your environment (GitLab version, runner type, etc.)

### Submitting Changes

1. **Fork the repository**
2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes**
   - Follow the existing code style
   - Add comments for complex logic
   - Update documentation if needed
4. **Test your changes**
   - Verify templates work in a test GitLab project
   - Ensure no syntax errors in YAML files
   - Run local pre-script matrix checks: `hack/test-pre-matrix.sh`
5. **Commit your changes**
   ```bash
   git commit -m "feat: brief description of your change"
   ```
   - Use conventional commit format: `feat:`, `fix:`, `docs:`, `refactor:`
6. **Push and create a Pull Request**
   ```bash
   git push origin feature/your-feature-name
   ```

### Development Guidelines

#### YAML Style
- Use 2 spaces for indentation
- Quote strings containing special characters
- Keep lines under 120 characters
- Use `>` for multi-line strings when appropriate

#### Shell Script Style
- Use `#!/usr/bin/env bash` shebang
- Enable strict mode: `set -euo pipefail`
- Use meaningful variable names
- Add comments for complex logic

#### Dockerfile Style
- Use multi-stage builds when appropriate
- Pin base image versions
- Order layers by change frequency (least to most)
- Add LABEL metadata

### Project Structure

```
gitlab-ci-templates/
├── templates/          # Ready-to-use GitLab CI templates
├── jobs-templates/     # Reusable job definitions
├── utils/              # Utility job snippets
├── vars/               # Default variables
├── scripts/            # Shell scripts for CI jobs
├── dockerfile/         # Application Dockerfile templates
├── images/             # Source for CI builder images
└── .github/workflows/  # Image build pipelines
```

### Questions?

Feel free to open an issue for any questions or discussions.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
