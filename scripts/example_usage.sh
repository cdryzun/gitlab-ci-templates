#!/usr/bin/env bash

# Import utils file
source scripts/_utils.stable.sh

# Example 1: Convert PRE environment URL
test_url_pre="https://api.example.com/PRE/some-service"
result_pre=$(convert_url "$test_url_pre")
echo "PRE environment conversion result:"
echo "  Input:  $test_url_pre"
echo "  Output:  $result_pre"
echo ""

# Example 2: Convert TEST environment URL
test_url_test="https://api.example.com/TEST/another-service"
result_test=$(convert_url "$test_url_test")
echo "TEST environment conversion result:"
echo "  Input:  $test_url_test"
echo "  Output:  $result_test"
echo ""

# Example 3: Convert PROD environment URL
test_url_prod="https://api.example.com/PROD/production-service"
result_prod=$(convert_url "$test_url_prod")
echo "PROD environment conversion result:"
echo "  Input:  $test_url_prod"
echo "  Output:  $result_prod"
echo ""

# Example 4: Use in pipeline (in CI/CD scripts)
echo "Example usage in pipeline:"
echo "  target_url=\$(convert_url \"\${CI_REGISTRY_URL}\")"
echo "  echo \"\${target_url}\""
