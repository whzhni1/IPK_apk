#!/bin/bash

set -e

GITCODE_TOKEN="${GITCODE_TOKEN:-}"
USERNAME="${USERNAME:-whzhni}"
REPO_NAME="${REPO_NAME:-test-release}"
REPO_DESC="${REPO_DESC:-GitCode Release Repository}"
REPO_PRIVATE="${REPO_PRIVATE:-false}"
TAG_NAME="${TAG_NAME:-v1.0.0}"
RELEASE_TITLE="${RELEASE_TITLE:-Release ${TAG_NAME}}"
RELEASE_BODY="${RELEASE_BODY:-Release ${TAG_NAME}}"
BRANCH="${BRANCH:-main}"
UPLOAD_FILES="${UPLOAD_FILES:-}"
DEBUG="${DEBUG:-false}"

API_BASE="https://gitcode.com/api/v5"
REPO_PATH="${USERNAME}/${REPO_NAME}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; }
log_debug() { [ "$DEBUG" = "true" ] && echo -e "${BLUE}[DEBUG]${NC} $*"; }

api_get() {
    local endpoint="$1"
    local url="${API_BASE}${endpoint}"
    [ "$url" == *"?"* ] && url="${url}&access_token=${GITCODE_TOKEN}" || url="${url}?access_token=${GITCODE_TOKEN}"
    
    response=$(curl -s -w "\n%{http_code}" "$url")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -ge 400 ]; then
        echo "$body"
        return 1
    fi
    
    echo "$body"
}

api_post() {
    local endpoint="$1"
    local data="$2"
    local url="${API_BASE}${endpoint}"
    [ "$url" == *"?"* ] && url="${url}&access_token=${GITCODE_TOKEN}" || url="${url}?access_token=${GITCODE_TOKEN}"
    
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$data" \
        "$url")
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -ge 400 ]; then
        echo "$body"
        return 1
    fi
    
    echo "$body"
}

api_delete() {
    local endpoint="$1"
    local url="${API_BASE}${endpoint}?access_token=${GITCODE_TOKEN}"
    
    response=$(curl -s -w "\n%{http_code}" -X DELETE "$url")
    http_code=$(echo "$response" | tail -n1)
    
    [ "$http_code" -eq 204 ] || [ "$http_code" -eq 200 ] || [ "$http_code" -eq 404 ]
}

# 尝试多种方式获取上传 URL
get_upload_url() {
    local filename="$1"
    
    log_info "尝试获取上传 URL..."
    
    # 方式1: access_token in query
    log_debug "方式1: access_token query 参数"
    local url1="${API_BASE}/repos/${USERNAME}/${REPO_NAME}/releases/${TAG_NAME}/upload_url?access_token=${GITCODE_TOKEN}&file_name=${filename}"
    
    response=$(curl -s -w "\n%{http_code}" "$url1")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    log_debug "HTTP $http_code: ${body:0:200}"
    
    if [ "$http_code" -eq 200 ]; then
        log_success "方式1成功"
        echo "$body"
        return 0
    fi
    
    # 方式2: PRIVATE-TOKEN header (GitLab style)
    log_debug "方式2: PRIVATE-TOKEN header"
    local url2="${API_BASE}/repos/${USERNAME}/${REPO_NAME}/releases/${TAG_NAME}/upload_url?file_name=${filename}"
    
    response=$(curl -s -w "\n%{http_code}" \
        -H "PRIVATE-TOKEN: ${GITCODE_TOKEN}" \
        "$url2")
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    log_debug "HTTP $http_code: ${body:0:200}"
    
    if [ "$http_code" -eq 200 ]; then
        log_success "方式2成功"
        echo "$body"
        return 0
    fi
    
    # 方式3: Authorization Bearer
    log_debug "方式3: Authorization Bearer"
    
    response=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer ${GITCODE_TOKEN}" \
        "$url2")
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    log_debug "HTTP $http_code: ${body:0:200}"
    
    if [ "$http_code" -eq 200 ]; then
        log_success "方式3成功"
        echo "$body"
        return 0
    fi
    
    # 方式4: Authorization token (Gitee style)
    log_debug "方式4: Authorization token"
    
    response=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: token ${GITCODE_TOKEN}" \
        "$url2")
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    log_debug "HTTP $http_code: ${body:0:200}"
    
    if [ "$http_code" -eq 200 ]; then
        log_success "方式4成功"
        echo "$body"
        return 0
    fi
    
    # 所有方式都失败
    log_error "所有认证方式均失败"
    echo ""
    echo "错误详情:"
    echo "$body"
    echo ""
    echo "可能的原因:"
    echo "1. Token 缺少特定权限（虽然界面显示已勾选全部）"
    echo "2. GitCode API 的这个功能可能有限制或 bug"
    echo "3. 需要联系 GitCode 支持确认权限配置"
    echo ""
    echo "建议操作:"
    echo "1. 访问 GitCode 设置 → 访问令牌"
    echo "2. 删除现有 Token，重新创建"
    echo "3. 确保勾选了所有项目相关权限"
    echo "4. 或者联系 GitCode 技术支持"
    
    return 1
}

upload_file_to_release() {
    local file="$1"
    local filename=$(basename "$file")
    
    log_info "上传: $filename ($(du -h "$file" | cut -f1))"
    
    # 获取上传 URL
    upload_info=$(get_upload_url "$filename")
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # 提取 URL
    if command -v jq &> /dev/null; then
        upload_url=$(echo "$upload_info" | jq -r '.url // empty')
    else
        upload_url=$(echo "$upload_info" | grep -o '"url":"[^"]*"' | head -1 | cut -d'"' -f4)
    fi
    
    if [ -z "$upload_url" ]; then
        log_error "无法提取上传 URL"
        log_debug "响应: $upload_info"
        return 1
    fi
    
    log_debug "上传 URL: ${upload_url:0:50}..."
    log_info "执行 PUT 上传..."
    
    # 上传文件
    response=$(curl -s -w "\n%{http_code}" -X PUT \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@${file}" \
        "$upload_url")
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    log_debug "上传响应 HTTP $http_code"
    
    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ] || [ "$http_code" -eq 204 ]; then
        log_success "上传成功"
        return 0
    else
        log_error "上传失败 (HTTP $http_code)"
        log_debug "响应: ${body:0:300}"
        return 1
    fi
}

check_token() {
    echo ""
    log_info "检查环境配置"
    
    if [ -z "$GITCODE_TOKEN" ]; then
        log_error "GITCODE_TOKEN 未设置"
        exit 1
    fi
    
    log_success "Token 已配置"
    
    # 测试 Token 有效性
    log_info "测试 Token 权限..."
    
    user_info=$(api_get "/user" 2>&1)
    
    if echo "$user_info" | grep -q '"login"'; then
        if command -v jq &> /dev/null; then
            user_login=$(echo "$user_info" | jq -r '.login')
            log_success "Token 有效 (用户: $user_login)"
        else
            log_success "Token 有效"
        fi
    else
        log_warning "Token 可能权限不足"
    fi
}

ensure_repository() {
    echo ""
    log_info "步骤 1/5: 检查仓库"
    
    if ! api_get "/repos/${REPO_PATH}" >/dev/null 2>&1; then
        log_warning "仓库不存在，创建中..."
        
        private_val="false"
        [ "$REPO_PRIVATE" = "true" ] && private_val="true"
        
        if ! api_post "/user/repos" "{
            \"name\": \"${REPO_NAME}\",
            \"description\": \"${REPO_DESC}\",
            \"private\": ${private_val},
            \"has_issues\": true,
            \"has_wiki\": true,
            \"auto_init\": false
        }" >/dev/null; then
            log_error "仓库创建失败"
            exit 1
        fi
        
        log_success "仓库创建成功"
        sleep 5
    else
        log_success "仓库已存在"
    fi
}

ensure_branch() {
    echo ""
    log_info "步骤 2/5: 检查分支"
    
    if api_get "/repos/${REPO_PATH}/branches/${BRANCH}" >/dev/null 2>&1; then
        log_success "分支已存在"
        return 0
    fi
    
    log_warning "分支不存在，创建中..."
    
    [ -f ".git/shallow" ] && { git fetch --unshallow || { rm -rf .git; git init; }; }
    [ ! -d ".git" ] && git init
    
    git config user.name "GitCode Bot"
    git config user.email "bot@gitcode.com"
    
    [ ! -f "README.md" ] && echo -e "# ${REPO_NAME}\n\n${REPO_DESC}" > README.md
    
    git add -A
    git diff --cached --quiet && git commit --allow-empty -m "Initial commit" || git commit -m "Initial commit"
    
    local git_url="https://oauth2:${GITCODE_TOKEN}@gitcode.com/${REPO_PATH}.git"
    git remote get-url gitcode &>/dev/null && git remote set-url gitcode "$git_url" || git remote add gitcode "$git_url"
    
    git push gitcode HEAD:refs/heads/${BRANCH} 2>&1 | sed "s/${GITCODE_TOKEN}/***TOKEN***/g" || {
        log_error "推送失败"
        exit 1
    }
    
    log_success "分支创建成功"
    sleep 3
}

cleanup_old_tags() {
    echo ""
    log_info "步骤 3/5: 清理旧标签"
    
    response=$(api_get "/repos/${REPO_PATH}/tags" 2>/dev/null || echo "")
    
    if [ -z "$response" ] || ! echo "$response" | grep -q '\['; then
        log_info "没有旧标签"
        return 0
    fi
    
    if command -v jq &> /dev/null; then
        tags=$(echo "$response" | jq -r '.[].name' 2>/dev/null)
    else
        tags=$(echo "$response" | grep -o '{"name":"[^"]*"' | cut -d'"' -f4)
    fi
    
    if [ -z "$tags" ]; then
        log_info "没有旧标签"
        return 0
    fi
    
    deleted=0
    while IFS= read -r tag; do
        [ -z "$tag" ] || [ "$tag" = "$TAG_NAME" ] && continue
        
        if ! echo "$tag" | grep -qE '^(v[0-9]|[0-9])'; then
            log_debug "跳过无效标签: $tag"
            continue
        fi
        
        log_warning "删除: $tag"
        
        if api_delete "/repos/${REPO_PATH}/tags/${tag}"; then
            log_success "已删除"
            deleted=$((deleted + 1))
        fi
        
        sleep 1
    done <<< "$tags"
    
    if [ $deleted -gt 0 ]; then
        log_info "已删除 $deleted 个旧标签"
    else
        log_info "没有需要删除的标签"
    fi
}

create_release() {
    echo ""
    log_info "步骤 4/5: 创建 Release"
    log_info "标签: ${TAG_NAME}"
    log_info "标题: ${RELEASE_TITLE}"
    
    body_escaped=$(echo "$RELEASE_BODY" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
    
    if ! response=$(api_post "/repos/${REPO_PATH}/releases" "{
        \"tag_name\": \"${TAG_NAME}\",
        \"name\": \"${RELEASE_TITLE}\",
        \"body\": \"${body_escaped}\",
        \"target_commitish\": \"${BRANCH}\"
    }"); then
        log_error "创建失败"
        exit 1
    fi
    
    if echo "$response" | grep -q "\"tag_name\":\"${TAG_NAME}\""; then
        log_success "Release 创建成功"
    else
        log_error "创建失败"
        exit 1
    fi
}

upload_files() {
    echo ""
    log_info "步骤 5/5: 上传文件到 Release 附件"
    
    if [ -z "$UPLOAD_FILES" ]; then
        log_info "没有文件需要上传"
        return 0
    fi
    
    uploaded=0
    failed=0
    
    IFS=' ' read -ra FILES <<< "$UPLOAD_FILES"
    total=${#FILES[@]}
    
    for file in "${FILES[@]}"; do
        [ -z "$file" ] && continue
        
        if [ ! -f "$file" ]; then
            log_warning "文件不存在: $file"
            failed=$((failed + 1))
            continue
        fi
        
        echo ""
        log_info "[$(( uploaded + failed + 1 ))/${total}] $(basename "$file")"
        
        if upload_file_to_release "$file"; then
            uploaded=$((uploaded + 1))
        else
            failed=$((failed + 1))
        fi
    done
    
    echo ""
    
    if [ $uploaded -gt 0 ]; then
        log_success "上传完成: $uploaded 成功, $failed 失败"
    else
        log_error "所有文件上传失败"
        echo ""
        echo "请尝试以下操作:"
        echo "1. 重新生成 GitCode Token"
        echo "2. 联系 GitCode 支持确认 API 权限问题"
        echo "3. 或手动在网页上传文件: https://gitcode.com/${REPO_PATH}/releases"
    fi
}

verify_release() {
    echo ""
    log_info "验证 Release"
    
    if response=$(api_get "/repos/${REPO_PATH}/releases/tags/${TAG_NAME}"); then
        log_success "验证成功"
        
        if command -v jq &> /dev/null; then
            assets_count=$(echo "$response" | jq '.assets | length')
            log_info "附件数量: $assets_count"
        fi
    else
        log_error "验证失败"
        exit 1
    fi
}

main() {
    echo ""
    echo "GitCode Release 发布脚本"
    echo ""
    echo "仓库: ${REPO_PATH}"
    echo "标签: ${TAG_NAME}"
    echo "调试模式: ${DEBUG}"
    
    check_token
    ensure_repository
    ensure_branch
    cleanup_old_tags
    create_release
    upload_files
    verify_release
    
    echo ""
    log_success "🎉 Release 创建完成"
    echo ""
    echo "访问: https://gitcode.com/${REPO_PATH}/releases"
    echo ""
}

main "$@"
