#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1"; exit 1; }

assert_env_equals() {
  local env_file="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual="$(awk -F= -v k="$key" '$1==k {print substr($0, index($0,$2))}' "$env_file" | tail -n1)"
  if [[ "$actual" != "$expected" ]]; then
    echo "Expected $key=$expected, got ${actual:-<unset>}"
    return 1
  fi
}

base_env() {
  export CI_PROJECT_DIR="$1"
  export CI_PROJECT_NAME='demo'
  export CI_PROJECT_NAMESPACE='team/sub'
  export CI_COMMIT_SHORT_SHA='abc1234'
  export CI_PIPELINE_ID='100'
  export RELEASE_BUILD='false'
  export LOG_LEVEL='info'
  export PROJECT_TYPE=''
  export BUILD_SHELL='echo build'
  export PACKAGE_MANAGER='pnpm'
  export DOCKER_REGISTRY='docker.io'
  export DOCKER_HUB_ORGANIZATION='demoorg'
  export ENV_FILE='build.env'
  export FEAT_DOCKER_IMAGE_BUILD='false'
  export DOCKERFILE_BUILD_JDK_VERSION='17-alpine'
  export MAVEN_IMAGE='ghcr.io/cdryzun/glci-builder-java:jdk17'
  export NODE_IMAGE='ghcr.io/cdryzun/glci-builder-nodejs:20'
  export PYTHON_IMAGE='ghcr.io/cdryzun/glci-builder-python:3.11'
  export GO_IMAGE='ghcr.io/cdryzun/glci-builder-golang:1.23'
  export TOOLBOX_IMAGE='ghcr.io/cdryzun/glci-toolbox:latest'
  export BASE_BUILD_IMAGE=''
  export PRD_BUILD_CREATE_TAG='true'
  export CUSTOM_DOCKERFILE_PATH=''
  export CUSTOM_DOCKERFILE_STRICT_CHECK='false'
  unset CUSTOM_REMOTE_SIT_BRANCH CUSTOM_REMOTE_PRD_BRANCH CUSTOME_REMOTE_SIT_BRANCH CUSTOME_REMOTE_PRD_BRANCH FEAT_BRANCH
}

run_case() {
  local script_name="$1"
  local setup_fn="$2"
  local check_fn="$3"

  local tmpdir
  tmpdir="$(mktemp -d)"
  cp "$ROOT_DIR/scripts/_utils.stable.sh" "$tmpdir/_utils.sh"
  cp "$ROOT_DIR/scripts/${script_name}" "$tmpdir/pre.sh"

  # default marker for project detection
  echo '{}' > "$tmpdir/package.json"

  (
    cd "$tmpdir"
    base_env "$tmpdir"
    "$setup_fn" "$tmpdir"
    bash pre.sh > /dev/null 2>&1 || fail "${script_name}:${setup_fn} execution failed"
    "$check_fn" "$tmpdir/build.env" || fail "${script_name}:${setup_fn} assertion failed"
  )
  rm -rf "$tmpdir"
  pass "${script_name}:${setup_fn}"
}

setup_feat_case() {
  local dir="$1"
  export CI_COMMIT_REF_NAME='feature/new-ui'
  export FEAT_DOCKER_IMAGE_BUILD='TRUE'
}

check_feat_case() {
  local env_file="$1"
  assert_env_equals "$env_file" "FEAT_BRANCH" "true"
  assert_env_equals "$env_file" "DOCKER_IMAGE_BUILD" "true"
}

setup_custom_sit_preferred() {
  local dir="$1"
  export CI_COMMIT_REF_NAME='sit'
  export CUSTOM_REMOTE_SIT_BRANCH='uat'
  export CUSTOME_REMOTE_SIT_BRANCH='qa'
}

check_custom_sit_preferred() {
  local env_file="$1"
  assert_env_equals "$env_file" "BUILD_ENV" "uat"
  assert_env_equals "$env_file" "REMOTE_BRANCH" "uat"
}

setup_release_tag() {
  local dir="$1"
  echo '<project></project>' > "$dir/pom.xml"
  rm -f "$dir/package.json"
  export PROJECT_TYPE='java'
  export CI_COMMIT_REF_NAME='v2.0.1'
  export RELEASE_BUILD='TRUE'
}

check_release_tag() {
  local env_file="$1"
  assert_env_equals "$env_file" "DOCKER_IMAGE_TAG" "2.0.1"
  assert_env_equals "$env_file" "BUILD_ENV" "prd"
}

setup_prd_hotfix_custom() {
  local dir="$1"
  export CI_COMMIT_REF_NAME='prd-hotfix'
  export CUSTOM_REMOTE_PRD_BRANCH='prod'
}

check_prd_hotfix_custom() {
  local env_file="$1"
  assert_env_equals "$env_file" "BUILD_ENV" "prod"
  assert_env_equals "$env_file" "REMOTE_BRANCH" "prod"
}

setup_dockerfile_strict_false() {
  local dir="$1"
  echo 'FROM alpine:3.20
CMD ["echo","hi"]' > "$dir/Dockerfile"
  export CI_COMMIT_REF_NAME='dev'
  export CUSTOM_DOCKERFILE_PATH='Dockerfile'
  export CUSTOM_DOCKERFILE_STRICT_CHECK='false'
}

check_dockerfile_strict_false() {
  local env_file="$1"
  assert_env_equals "$env_file" "CUSTOM_DOCKERFILE" "true"
}

# --- New test cases ---

# Branch name with slashes should be converted to dashes
setup_branch_slash_convert() {
  local dir="$1"
  export CI_COMMIT_REF_NAME='feature/user/login'
}

check_branch_slash_convert() {
  local env_file="$1"
  assert_env_equals "$env_file" "_CI_COMMIT_REF_NAME" "feature-user-login"
}

# prd-* branch with no custom override falls back to prd
setup_prd_hotfix_no_custom() {
  local dir="$1"
  export CI_COMMIT_REF_NAME='prd-hotfix'
}

check_prd_hotfix_no_custom() {
  local env_file="$1"
  assert_env_equals "$env_file" "BUILD_ENV" "prd"
  assert_env_equals "$env_file" "REMOTE_BRANCH" "prd"
}

# Custom JDK version: DOCKERFILE_BUILD_JDK_VERSION=21-alpine → MAVEN_IMAGE jdk21
setup_custom_jdk_version() {
  local dir="$1"
  echo '<project></project>' > "$dir/pom.xml"
  rm -f "$dir/package.json"
  export PROJECT_TYPE='java'
  export CI_COMMIT_REF_NAME='dev'
  export DOCKERFILE_BUILD_JDK_VERSION='21-alpine'
}

check_custom_jdk_version() {
  local env_file="$1"
  assert_env_equals "$env_file" "MAVEN_IMAGE" "ghcr.io/cdryzun/glci-builder-java:jdk21"
}

# FEAT_BRANCH unset on non-feat branch: DOCKER_IMAGE_BUILD should not be forced false
setup_non_feat_branch() {
  local dir="$1"
  export CI_COMMIT_REF_NAME='dev'
}

check_non_feat_branch() {
  local env_file="$1"
  assert_env_equals "$env_file" "BUILD_ENV" "dev"
  assert_env_equals "$env_file" "REMOTE_BRANCH" "dev"
}

# PRD_BUILD_CREATE_TAG should be reset to false when REMOTE_BRANCH != prd
setup_prd_create_tag_non_prd() {
  local dir="$1"
  export CI_COMMIT_REF_NAME='sit'
  export PRD_BUILD_CREATE_TAG='true'
}

check_prd_create_tag_non_prd() {
  local env_file="$1"
  assert_env_equals "$env_file" "PRD_BUILD_CREATE_TAG" "false"
}

main() {
  bash -n "$ROOT_DIR/scripts/pre.latest.sh"
  bash -n "$ROOT_DIR/scripts/pre.stable.sh"

  for script in pre.latest.sh pre.stable.sh; do
    run_case "$script" setup_feat_case check_feat_case
    run_case "$script" setup_custom_sit_preferred check_custom_sit_preferred
    run_case "$script" setup_release_tag check_release_tag
    run_case "$script" setup_prd_hotfix_custom check_prd_hotfix_custom
    run_case "$script" setup_dockerfile_strict_false check_dockerfile_strict_false
    run_case "$script" setup_branch_slash_convert check_branch_slash_convert
    run_case "$script" setup_prd_hotfix_no_custom check_prd_hotfix_no_custom
    run_case "$script" setup_custom_jdk_version check_custom_jdk_version
    run_case "$script" setup_non_feat_branch check_non_feat_branch
    run_case "$script" setup_prd_create_tag_non_prd check_prd_create_tag_non_prd
  done

  echo "All pre-script matrix tests passed."
}

main "$@"
