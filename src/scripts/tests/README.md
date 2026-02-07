# Playback Test Suite

Comprehensive security and network isolation tests for the Playback application.

## Overview

This test suite ensures that Playback adheres to its core security principles:
1. **File Security**: Sensitive screen recordings are protected with proper file permissions
2. **Database Security**: SQLite database uses secure_delete and WAL mode
3. **Input Validation**: All user inputs are validated and sanitized
4. **Network Isolation**: Zero network access - all data stays local

## Test Files

### test_security.py

Security tests covering file permissions, database security, and input validation.

**Test Classes:**
- `TestFilePermissions` - File and directory permission enforcement
- `TestDatabaseSecurity` - Database security settings and pragmas
- `TestInputValidation` - Input sanitization and SQL injection prevention
- `TestErrorMessageSanitization` - Error message security
- `TestPermissionEnforcement` - Security enforcement across codebase

**Key Tests:**
- Secure file creation with 0o600 permissions
- Database secure_delete pragma enabled
- Directory permissions (0o700 for data, 0o755 for logs)
- Bundle ID validation (alphanumeric + dots/hyphens only)
- SQL injection prevention
- WAL and SHM file permissions

**Total Tests:** 24

### test_network.py

Network isolation tests verifying zero-network policy compliance.

**Test Classes:**
- `TestNetworkImports` - Network library import detection
- `TestNetworkURLs` - HTTP/HTTPS URL detection
- `TestSubprocessNetworkTools` - Network tool subprocess calls
- `TestNetworkPolicyCompliance` - Comprehensive policy compliance
- `TestCodebaseStats` - Informational statistics

**Key Tests:**
- No urllib, requests, socket imports
- No HTTP/HTTPS URLs in code
- No curl, wget subprocess calls
- No telemetry or analytics code
- No update check mechanisms
- Codebase scanning statistics

**Total Tests:** 14

## Running Tests

### All Tests
```bash
python3 -m pytest src/scripts/tests/ -v
```

### Security Tests Only
```bash
python3 -m pytest src/scripts/tests/test_security.py -v
```

### Network Tests Only
```bash
python3 -m pytest src/scripts/tests/test_network.py -v
```

### Specific Test Class
```bash
python3 -m pytest src/scripts/tests/test_security.py::TestFilePermissions -v
```

### Single Test
```bash
python3 -m pytest src/scripts/tests/test_security.py::TestFilePermissions::test_secure_file_creation_permissions -v
```

### With Coverage
```bash
python3 -m pytest src/scripts/tests/ --cov=src/lib --cov=src/scripts --cov-report=html
```

## Test Results

Current status: **38 tests, all passing**

- Security tests: 24 passed
- Network tests: 14 passed

## Requirements

- Python 3.12+
- pytest 7.0+

Install dependencies:
```bash
sudo apt-get install python3-pytest
# or
pip3 install pytest
```

## Test Coverage

### File Security
- ✅ Secure file creation (0o600)
- ✅ Directory permissions (0o700/0o755)
- ✅ Database file permissions
- ✅ WAL and SHM file permissions
- ✅ No world-readable sensitive files
- ✅ Umask restoration

### Database Security
- ✅ secure_delete pragma enabled
- ✅ WAL mode enabled
- ✅ Integrity checks
- ✅ Read-only connections

### Input Validation
- ✅ Bundle ID validation
- ✅ Config value validation
- ✅ SQL injection prevention
- ✅ Path traversal prevention
- ✅ Segment ID format validation

### Network Isolation
- ✅ No network library imports
- ✅ No HTTP/HTTPS URLs
- ✅ No subprocess network tools
- ✅ No telemetry/analytics
- ✅ No update checks

## Design Principles

1. **Fail Fast**: Tests immediately flag security violations
2. **Comprehensive**: Cover all attack vectors and security boundaries
3. **Self-Documenting**: Clear test names and assertions
4. **Maintainable**: Well-organized with fixtures and helpers
5. **Fast**: All tests run in under 1 second

## Adding New Tests

When adding new features, add corresponding security tests:

1. **New file operations**: Add permission tests
2. **New database tables**: Add security pragma tests
3. **New user inputs**: Add validation tests
4. **New imports**: Verify no network libraries
5. **New subprocess calls**: Verify no network tools

## CI/CD Integration

These tests should run on:
- Every commit (pre-commit hook)
- Every pull request
- Before releases
- Scheduled daily runs

Example GitHub Actions workflow:
```yaml
- name: Run Security Tests
  run: python3 -m pytest src/scripts/tests/ -v --tb=short
```

## Troubleshooting

### Test Failures

If tests fail, check:
1. File permissions on production database
2. Config file format and values
3. Recent code changes to security-sensitive areas
4. New imports or dependencies

### False Positives

Network tests may flag false positives for:
- Comments containing URLs (filtered out)
- Test files themselves (excluded from scan)
- Documentation strings (use `#` comments)

## Security Policy

Playback is a **local-only application**. All data stays on the user's machine:
- No telemetry or analytics
- No crash reporting
- No update checks over network
- No cloud sync
- No API calls

These tests enforce this policy at the code level.
