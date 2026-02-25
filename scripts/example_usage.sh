#!/usr/bin/env bash

# 引入 utils 文件
source scripts/_utils.stable.sh

# 示例 1: 转换 PRE 环境 URL
test_url_pre="https://api.example.com/PRE/some-service"
result_pre=$(convert_url "$test_url_pre")
echo "PRE 环境转换结果:"
echo "  输入:  $test_url_pre"
echo "  输出:  $result_pre"
echo ""

# 示例 2: 转换 TEST 环境 URL
test_url_test="https://api.example.com/TEST/another-service"
result_test=$(convert_url "$test_url_test")
echo "TEST 环境转换结果:"
echo "  输入:  $test_url_test"
echo "  输出:  $result_test"
echo ""

# 示例 3: 转换 PROD 环境 URL
test_url_prod="https://api.example.com/PROD/production-service"
result_prod=$(convert_url "$test_url_prod")
echo "PROD 环境转换结果:"
echo "  输入:  $test_url_prod"
echo "  输出:  $result_prod"
echo ""

# 示例 4: 在流水线中使用 (CI/CD 脚本中)
echo "在流水线中的使用示例:"
echo "  target_url=\$(convert_url \"\${CI_REGISTRY_URL}\")"
echo "  echo \"\${target_url}\""
