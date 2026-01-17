# Contributing

## Running Tests

Run all automated tests:
```bash
./test/run-tests
```

This runs:
- **Shellcheck** - Lints all bash scripts in `bin/` and `test/`
- **Macro expansion tests** - Validates `@file`, `@basename` macros

Shellcheck is optional - tests will skip it with a warning if not installed.

## Test Environment

Launch Neovim with the plugin loaded from local directory:
```bash
./test/nvim-test [file...]
```

This creates an isolated test environment with:
- Plugin loaded from current directory (not installed version)
- Test data stored in `.test-data/` (gitignored)
- Minimal sensible defaults

## CI/CD

Tests automatically run on:
- Pull requests to `main`
- Pushes to `main` branch

CI environment includes:
- Latest stable Neovim
- Shellcheck for bash script linting
- All test suites (shellcheck + macro tests)

See `.github/workflows/test.yml` for configuration.
