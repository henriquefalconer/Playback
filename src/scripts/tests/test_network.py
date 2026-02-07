#!/usr/bin/env python3
"""
Network isolation tests for Playback application.

Verifies zero-network policy compliance by scanning codebase for:
- Network library imports (urllib, requests, socket, http)
- HTTP/HTTPS URLs in code
- Subprocess calls to network tools (curl, wget)
- Any other network-related functionality

Playback is a local-only application - all data stays on the user's machine.
No telemetry, no analytics, no cloud sync, no updates over network.

Run with: python3 -m pytest src/scripts/tests/test_network.py -v
"""

import ast
import re
from pathlib import Path
from typing import List, Set, Tuple

import pytest

# Add parent directory to path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))


# Network-related modules that should never be imported
FORBIDDEN_NETWORK_IMPORTS = {
    # HTTP clients
    "urllib",
    "urllib.request",
    "urllib.parse",
    "urllib3",
    "requests",
    "http",
    "http.client",
    "httplib",
    "httplib2",
    "aiohttp",

    # Sockets and networking
    "socket",
    "socketserver",
    "ssl",
    "asyncio.streams",

    # FTP
    "ftplib",

    # SMTP / Email
    "smtplib",
    "email",
    "imaplib",
    "poplib",

    # Web frameworks (should never be used)
    "flask",
    "django",
    "tornado",
    "twisted",
    "fastapi",

    # Cloud SDKs (should never be used)
    "boto3",
    "google.cloud",
    "azure",
    "botocore",
}

# Network tools that should never be called via subprocess
FORBIDDEN_NETWORK_TOOLS = {
    "curl",
    "wget",
    "nc",
    "netcat",
    "telnet",
    "ftp",
    "ssh",
    "scp",
    "rsync",
    "ping",
    "traceroute",
    "nslookup",
    "dig",
}

# Patterns that indicate network URLs
URL_PATTERNS = [
    r'https?://[^\s\'"]+',  # HTTP/HTTPS URLs
    r'ftps?://[^\s\'"]+',    # FTP URLs
    r'wss?://[^\s\'"]+',     # WebSocket URLs
]


def get_python_source_files() -> List[Path]:
    """
    Get all Python source files in the project.

    Returns:
        List of Path objects for all .py files (excluding tests and venv).
    """
    project_root = Path(__file__).resolve().parent.parent.parent.parent
    python_files = []

    # Search in src/scripts and src/lib
    for search_dir in ["src/scripts", "src/lib"]:
        search_path = project_root / search_dir
        if search_path.exists():
            for py_file in search_path.rglob("*.py"):
                # Exclude test files from scanning (we only scan production code)
                # Check for "test" or "tests" in any part of the path
                path_parts_lower = [p.lower() for p in py_file.parts]
                if any("test" in part for part in path_parts_lower):
                    continue
                if py_file.name.startswith("test_"):
                    continue
                python_files.append(py_file)

    return python_files


def get_imports_from_file(file_path: Path) -> Set[str]:
    """
    Extract all import statements from a Python file using AST.

    Args:
        file_path: Path to Python file to analyze.

    Returns:
        Set of imported module names.
    """
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            source = f.read()

        tree = ast.parse(source, filename=str(file_path))
        imports = set()

        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    imports.add(alias.name)
            elif isinstance(node, ast.ImportFrom):
                if node.module:
                    imports.add(node.module)

        return imports

    except (SyntaxError, UnicodeDecodeError) as e:
        # If file can't be parsed, skip it (might be generated or corrupted)
        print(f"Warning: Could not parse {file_path}: {e}")
        return set()


def find_subprocess_calls(file_path: Path) -> List[Tuple[int, str]]:
    """
    Find subprocess calls in a Python file.

    Args:
        file_path: Path to Python file to analyze.

    Returns:
        List of (line_number, command) tuples for subprocess calls.
    """
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            lines = f.readlines()

        subprocess_calls = []

        for i, line in enumerate(lines, start=1):
            # Look for subprocess.run, subprocess.call, subprocess.Popen, etc.
            if "subprocess." in line and any(call in line for call in ["run", "call", "Popen", "check_output"]):
                subprocess_calls.append((i, line.strip()))

        return subprocess_calls

    except (UnicodeDecodeError, IOError) as e:
        print(f"Warning: Could not read {file_path}: {e}")
        return []


def find_urls_in_file(file_path: Path) -> List[Tuple[int, str]]:
    """
    Find HTTP/HTTPS URLs in a Python file.

    Args:
        file_path: Path to Python file to analyze.

    Returns:
        List of (line_number, url) tuples.
    """
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            lines = f.readlines()

        urls_found = []

        for i, line in enumerate(lines, start=1):
            # Skip comments
            if line.strip().startswith("#"):
                continue

            # Check each URL pattern
            for pattern in URL_PATTERNS:
                matches = re.findall(pattern, line)
                for match in matches:
                    urls_found.append((i, match))

        return urls_found

    except (UnicodeDecodeError, IOError) as e:
        print(f"Warning: Could not read {file_path}: {e}")
        return []


class TestNetworkImports:
    """Test suite for network import detection."""

    def test_no_network_imports_in_codebase(self):
        """Test that no files import network-related modules."""
        python_files = get_python_source_files()
        assert len(python_files) > 0, "No Python files found to scan"

        violations = []

        for py_file in python_files:
            imports = get_imports_from_file(py_file)

            # Check for forbidden imports
            for forbidden in FORBIDDEN_NETWORK_IMPORTS:
                # Check exact match or prefix match (e.g., "urllib.request")
                for imported in imports:
                    if imported == forbidden or imported.startswith(f"{forbidden}."):
                        violations.append(f"{py_file}: imports {imported}")

        assert len(violations) == 0, \
            f"Found network imports in codebase:\n" + "\n".join(violations)

    def test_no_urllib_imports(self):
        """Test specifically for urllib imports (common accidental network use)."""
        python_files = get_python_source_files()
        violations = []

        for py_file in python_files:
            imports = get_imports_from_file(py_file)

            # Check for any urllib variant
            for imported in imports:
                if "urllib" in imported.lower():
                    violations.append(f"{py_file}: imports {imported}")

        assert len(violations) == 0, \
            f"Found urllib imports:\n" + "\n".join(violations)

    def test_no_requests_imports(self):
        """Test specifically for requests library imports."""
        python_files = get_python_source_files()
        violations = []

        for py_file in python_files:
            imports = get_imports_from_file(py_file)

            if "requests" in imports:
                violations.append(f"{py_file}: imports requests")

        assert len(violations) == 0, \
            f"Found requests imports:\n" + "\n".join(violations)

    def test_no_socket_imports(self):
        """Test specifically for socket imports (low-level networking)."""
        python_files = get_python_source_files()
        violations = []

        for py_file in python_files:
            imports = get_imports_from_file(py_file)

            if "socket" in imports or "socketserver" in imports:
                violations.append(f"{py_file}: imports socket-related module")

        assert len(violations) == 0, \
            f"Found socket imports:\n" + "\n".join(violations)


class TestNetworkURLs:
    """Test suite for HTTP/HTTPS URL detection in code."""

    def test_no_http_urls_in_codebase(self):
        """Test that no files contain HTTP/HTTPS URLs."""
        python_files = get_python_source_files()
        assert len(python_files) > 0, "No Python files found to scan"

        violations = []

        for py_file in python_files:
            urls = find_urls_in_file(py_file)

            for line_num, url in urls:
                violations.append(f"{py_file}:{line_num}: {url}")

        assert len(violations) == 0, \
            f"Found HTTP/HTTPS URLs in codebase:\n" + "\n".join(violations)

    def test_no_api_endpoints_in_code(self):
        """Test that no files reference API endpoints."""
        python_files = get_python_source_files()
        api_patterns = [
            r'api\.',
            r'/api/',
            r'endpoint',
            r'\.com[/\s]',
            r'\.io[/\s]',
        ]

        violations = []

        for py_file in python_files:
            try:
                with open(py_file, "r", encoding="utf-8") as f:
                    content = f.read()

                for pattern in api_patterns:
                    if re.search(pattern, content, re.IGNORECASE):
                        # Only flag if it's not in a comment
                        lines = content.split("\n")
                        for i, line in enumerate(lines, start=1):
                            if re.search(pattern, line, re.IGNORECASE):
                                if not line.strip().startswith("#"):
                                    violations.append(f"{py_file}:{i}: matches '{pattern}'")

            except (UnicodeDecodeError, IOError):
                pass

        # Allow some false positives - this is a guideline check
        # Adjust threshold based on actual codebase
        assert len(violations) == 0, \
            f"Found potential API references:\n" + "\n".join(violations[:10])


class TestSubprocessNetworkTools:
    """Test suite for subprocess calls to network tools."""

    def test_no_curl_in_subprocess_calls(self):
        """Test that no files call curl via subprocess."""
        python_files = get_python_source_files()
        violations = []

        for py_file in python_files:
            subprocess_calls = find_subprocess_calls(py_file)

            for line_num, call_line in subprocess_calls:
                if "curl" in call_line.lower():
                    violations.append(f"{py_file}:{line_num}: {call_line}")

        assert len(violations) == 0, \
            f"Found curl calls:\n" + "\n".join(violations)

    def test_no_wget_in_subprocess_calls(self):
        """Test that no files call wget via subprocess."""
        python_files = get_python_source_files()
        violations = []

        for py_file in python_files:
            subprocess_calls = find_subprocess_calls(py_file)

            for line_num, call_line in subprocess_calls:
                if "wget" in call_line.lower():
                    violations.append(f"{py_file}:{line_num}: {call_line}")

        assert len(violations) == 0, \
            f"Found wget calls:\n" + "\n".join(violations)

    def test_no_network_tools_in_subprocess(self):
        """Test that no files call network tools via subprocess."""
        python_files = get_python_source_files()
        violations = []

        for py_file in python_files:
            subprocess_calls = find_subprocess_calls(py_file)

            for line_num, call_line in subprocess_calls:
                # Check for each forbidden tool
                for tool in FORBIDDEN_NETWORK_TOOLS:
                    # Use word boundary to avoid false positives (e.g., "ping" in "sleeping")
                    if re.search(rf'\b{tool}\b', call_line.lower()):
                        violations.append(f"{py_file}:{line_num}: calls {tool}")

        assert len(violations) == 0, \
            f"Found network tool calls:\n" + "\n".join(violations)


class TestNetworkPolicyCompliance:
    """Test suite for overall network policy compliance."""

    def test_zero_network_policy_compliance(self):
        """
        Comprehensive test for zero-network policy compliance.

        Verifies:
        1. No network imports
        2. No HTTP/HTTPS URLs
        3. No subprocess calls to network tools
        4. No cloud SDK imports
        """
        python_files = get_python_source_files()
        assert len(python_files) > 0, "No Python files found"

        all_violations = []

        # Check imports
        for py_file in python_files:
            imports = get_imports_from_file(py_file)
            for forbidden in FORBIDDEN_NETWORK_IMPORTS:
                for imported in imports:
                    if imported == forbidden or imported.startswith(f"{forbidden}."):
                        all_violations.append(f"IMPORT: {py_file}: {imported}")

        # Check URLs
        for py_file in python_files:
            urls = find_urls_in_file(py_file)
            for line_num, url in urls:
                all_violations.append(f"URL: {py_file}:{line_num}: {url}")

        # Check subprocess calls
        for py_file in python_files:
            subprocess_calls = find_subprocess_calls(py_file)
            for line_num, call_line in subprocess_calls:
                for tool in FORBIDDEN_NETWORK_TOOLS:
                    if re.search(rf'\b{tool}\b', call_line.lower()):
                        all_violations.append(f"SUBPROCESS: {py_file}:{line_num}: {tool}")

        # Report all violations
        if all_violations:
            violation_summary = "\n".join(all_violations)
            pytest.fail(
                f"Network policy violations found ({len(all_violations)} total):\n\n"
                f"{violation_summary}\n\n"
                f"Playback must be a local-only application with zero network access."
            )

    def test_no_telemetry_or_analytics(self):
        """Test that no files contain telemetry or analytics code."""
        python_files = get_python_source_files()

        # Use word boundaries to avoid false positives
        telemetry_keywords = [
            r'\banalytics\b',
            r'\btelemetry\b',
            r'\btracking\b',
            r'\bmixpanel\b',
            r'\bsegment\.io\b',  # Specific to Segment analytics service
            r'\bamplitude\b',
            r'google analytics',
            r'ga\(',  # Google Analytics function
            r'\bgtag\b',
            r'\bheap\b',
            r'\bhotjar\b',
        ]

        violations = []

        for py_file in python_files:
            try:
                with open(py_file, "r", encoding="utf-8") as f:
                    lines = f.readlines()

                for i, line in enumerate(lines, start=1):
                    # Skip comments
                    if line.strip().startswith("#"):
                        continue

                    for keyword in telemetry_keywords:
                        if re.search(keyword, line, re.IGNORECASE):
                            violations.append(f"{py_file}:{i}: matches pattern '{keyword}'")

            except (UnicodeDecodeError, IOError):
                pass

        assert len(violations) == 0, \
            f"Found potential telemetry/analytics code:\n" + "\n".join(violations)

    def test_no_update_check_mechanisms(self):
        """Test that no files implement update checking."""
        python_files = get_python_source_files()

        update_keywords = [
            "update_check",
            "check_update",
            "latest_version",
            "version_check",
            "auto_update",
            "software_update",
        ]

        violations = []

        for py_file in python_files:
            try:
                with open(py_file, "r", encoding="utf-8") as f:
                    content = f.read().lower()

                for keyword in update_keywords:
                    if keyword in content:
                        lines = content.split("\n")
                        for i, line in enumerate(lines, start=1):
                            if keyword in line and not line.strip().startswith("#"):
                                violations.append(f"{py_file}:{i}: contains '{keyword}'")

            except (UnicodeDecodeError, IOError):
                pass

        # This is a soft check - some false positives expected
        # Main goal is to catch obvious update check implementations
        assert len(violations) == 0, \
            f"Found potential update check code:\n" + "\n".join(violations)


class TestCodebaseStats:
    """Test suite for codebase statistics (informational, always passes)."""

    def test_report_python_file_count(self):
        """Report number of Python files scanned."""
        python_files = get_python_source_files()
        file_count = len(python_files)

        print(f"\n✓ Scanned {file_count} Python files for network violations")
        assert file_count > 0

    def test_report_import_summary(self):
        """Report summary of all imports in codebase."""
        python_files = get_python_source_files()
        all_imports = set()

        for py_file in python_files:
            imports = get_imports_from_file(py_file)
            all_imports.update(imports)

        # Filter to stdlib and common modules
        stdlib_imports = {imp for imp in all_imports if not "." in imp or imp.startswith("lib.")}

        print(f"\n✓ Found {len(all_imports)} unique imports across codebase")
        print(f"✓ Stdlib/local imports: {len(stdlib_imports)}")

        # Report any non-stdlib imports (third-party)
        third_party = all_imports - stdlib_imports
        if third_party:
            print(f"✓ Third-party imports: {', '.join(sorted(third_party))}")

        assert True  # Informational only


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short", "-s"])
