#!/bin/bash

set -e

# 配置（通过环境变量传入）
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

# API 配置
API_BASE="https://gitcode.com/api/v5"
REPO_PATH="${USERNAME}/${REPO_NAME}"

# 颜色
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
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $*"; }

# API v5 请求
api_get() {
    local endpoint="$1"
    local url="${API_BASE}${endpoint}"
    [ "$url" == *"?"* ] && url="${url}&access_token=${GITCODE_TOKEN}" || url="${url}?access_token=${GITCODE_TOKEN}"
    
    response=$(curl -s -w "\n%{http_code}" "$url")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -ge 400 ]; then
        log_debug "GET $endpoint - HTTP $http_code"
        log_debug "Response: ${body:0:200}"
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
        log_debug "POST $endpoint - HTTP $http_code"
        log_debug "Request: ${data:0:200}"
        log_debug "Response: ${body:0:200}"
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
    body=$(echo "$response" | sed '$d')
    
    log_debug "DELETE $endpoint - HTTP $http_code"
    
    # 204 或 200 都算成功
    if [ "$http_code" -eq 204 ] || [ "$http_code" -eq 200 ]; then
        return 0
    else
        log_debug "Response: ${body:0:200}"
        return 1
    fi
}

check_token() {
    echo ""
    log_info "检查环境配置"
    
    if [ -z "$GITCODE_TOKEN" ]; then
        log_error "GITCODE_TOKEN 未设置"
        echo "请设置: export GITCODE_TOKEN='your_token'"
        exit 1
    fi
    
    log_success "Token 已配置"
}

ensure_repository() {
    echo ""
    log_info "步骤 1/6: 检查仓库 ${REPO_PATH}"
    
    if ! response=$(api_get "/repos/${REPO_PATH}"); then
        log_warning "仓库不存在，创建中..."
        
        private_val="false"
        [ "$REPO_PRIVATE" = "true" ] && private_val="true"
        
        if ! response=$(api_post "/user/repos" "{
            \"name\": \"${REPO_NAME}\",
            \"description\": \"${REPO_DESC}\",
            \"private\": ${private_val},
            \"has_issues\": true,
            \"has_wiki\": true,
            \"auto_init\": false
        }"); then
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
    log_info "步骤 2/6: 检查分支 ${BRANCH}"
    
    if response=$(api_get "/repos/${REPO_PATH}/branches/${BRANCH}"); then
        log_success "分支已存在"
        return 0
    fi
    
    log_warning "分支不存在，创建中..."
    
    # 检查是否是 shallow clone
    if [ -f ".git/shallow" ]; then
        log_info "检测到浅克隆，转换为完整仓库..."
        git fetch --unshallow || {
            log_warning "无法 unshallow，将创建新仓库"
            rm -rf .git
            git init
        }
    fi
    
    [ ! -d ".git" ] && git init
    
    git config user.name "GitCode Bot"
    git config user.email "bot@gitcode.com"
    
    # 确保有文件
    if [ ! -f "README.md" ]; then
        cat > README.md <<EOF
# ${REPO_NAME}

${REPO_DESC}

## 自动创建

创建时间: $(date '+%Y-%m-%d %H:%M:%S')
EOF
    fi
    
    if [ ! -f ".gitignore" ]; then
        cat > .gitignore <<EOF
.DS_Store
*.log
node_modules/
EOF
    fi
    
    git add -A
    
    if git diff --cached --quiet; then
        git commit --allow-empty -m "Initial commit"
    else
        git commit -m "Initial commit"
    fi
    
    # 设置远程仓库
    local git_url="https://oauth2:${GITCODE_TOKEN}@gitcode.com/${REPO_PATH}.git"
    
    if git remote get-url gitcode &>/dev/null; then
        git remote set-url gitcode "$git_url"
    else
        git remote add gitcode "$git_url"
    fi
    
    log_info "推送到远程仓库..."
    
    # 推送并正确处理错误
    push_output=$(git push gitcode HEAD:refs/heads/${BRANCH} 2>&1 | sed "s/${GITCODE_TOKEN}/***TOKEN***/g") || {
        log_error "分支推送失败"
        echo "$push_output"
        exit 1
    }
    
    log_success "分支创建成功"
    sleep 3
}

cleanup_old_tags() {
    echo ""
    log_info "步骤 3/6: 清理旧标签"
    
    if ! response=$(api_get "/repos/${REPO_PATH}/tags"); then
        log_warning "获取标签失败，可能仓库为空"
        return 0
    fi
    
    tags=$(echo "$response" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
    
    if [ -z "$tags" ]; then
        log_info "没有现有标签"
        return 0
    fi
    
    log_info "现有标签: $(echo "$tags" | tr '\n' ' ')"
    
    deleted=0
    while IFS= read -r tag; do
        [ -z "$tag" ] || [ "$tag" = "$TAG_NAME" ] && continue
        
        log_warning "删除标签: $tag"
        
        # 删除 release（使用 tag）
        if api_delete "/repos/${REPO_PATH}/releases/${tag}"; then
            log_debug "Release 删除成功"
        else
            log_debug "Release 不存在或删除失败（可忽略）"
        fi
        
        # 删除标签
        if api_delete "/repos/${REPO_PATH}/tags/${tag}"; then
            log_success "标签删除成功: $tag"
        else
            log_warning "标签删除失败: $tag"
        fi
        
        deleted=$((deleted + 1))
        sleep 1
    done <<< "$tags"
    
    [ $deleted -gt 0 ] && log_info "已处理 ${deleted} 个旧标签" || log_info "无需删除"
}

create_release() {
    echo ""
    log_info "步骤 4/6: 创建 Release"
    log_info "标签: ${TAG_NAME}"
    log_info "标题: ${RELEASE_TITLE}"
    
    # 转义特殊字符
    body_escaped=$(echo "$RELEASE_BODY" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
    
    if ! response=$(api_post "/repos/${REPO_PATH}/releases" "{
        \"tag_name\": \"${TAG_NAME}\",
        \"name\": \"${RELEASE_TITLE}\",
        \"body\": \"${body_escaped}\",
        \"target_commitish\": \"${BRANCH}\"
    }"); then
        log_error "Release 创建失败"
        exit 1
    fi
    
    # 尝试用 jq 或 python 解析 JSON
    if command -v jq &> /dev/null; then
        RELEASE_ID=$(echo "$response" | jq -r '.id // empty')
    elif command -v python3 &> /dev/null; then
        RELEASE_ID=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null || echo "")
    else
        RELEASE_ID=$(echo "$response" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
    fi
    
    # 检查是否创建成功
    if echo "$response" | grep -q "\"tag_name\":\"${TAG_NAME}\""; then
        log_success "Release 创建成功"
        if [ -n "$RELEASE_ID" ]; then
            log_info "Release ID: ${RELEASE_ID}"
        else
            log_warning "未能提取 Release ID"
            log_debug "响应内容: ${response:0:500}"
        fi
    else
        log_error "Release 创建失败，响应异常"
        exit 1
    fi
}

upload_files() {
    echo ""
    log_info "步骤 5/6: 上传文件"
    
    if [ -z "$UPLOAD_FILES" ]; then
        log_info "没有文件需要上传"
        return 0
    fi
    
    # 必须有 RELEASE_ID
    if [ -z "$RELEASE_ID" ]; then
        log_error "无法上传：未获取到 Release ID"
        log_info "尝试重新获取 Release 信息..."
        
        rel_response=$(api_get "/repos/${REPO_PATH}/releases/tags/${TAG_NAME}")
        
        if command -v jq &> /dev/null; then
            RELEASE_ID=$(echo "$rel_response" | jq -r '.id // empty')
        elif command -v python3 &> /dev/null; then
            RELEASE_ID=$(echo "$rel_response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null || echo "")
        else
            RELEASE_ID=$(echo "$rel_response" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
        fi
        
        if [ -z "$RELEASE_ID" ]; then
            log_error "仍然无法获取 Release ID，跳过文件上传"
            log_debug "响应: ${rel_response:0:500}"
            return 1
        else
            log_success "获取到 Release ID: ${RELEASE_ID}"
        fi
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
        
        size=$(du -h "$file" | cut -f1)
        filename=$(basename "$file")
        log_info "[$(( uploaded + failed + 1 ))/${total}] $filename ($size)"
        
        # 上传文件
        url="${API_BASE}/repos/${REPO_PATH}/releases/${RELEASE_ID}/attach_files?access_token=${GITCODE_TOKEN}"
        
        log_debug "上传 URL: /repos/${REPO_PATH}/releases/${RELEASE_ID}/attach_files"
        
        response=$(curl -s -w "\n%{http_code}" -X POST \
            -F "file=@${file}" \
            "$url")
        
        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | sed '$d')
        
        log_debug "HTTP Code: $http_code"
        
        if [ "$http_code" -eq 201 ] || [ "$http_code" -eq 200 ]; then
            if echo "$body" | grep -q '"name"'; then
                log_success "上传成功"
                uploaded=$((uploaded + 1))
            else
                log_warning "上传可能成功但响应异常"
                log_debug "响应: ${body:0:200}"
                uploaded=$((uploaded + 1))
            fi
        else
            log_error "上传失败"
            log_debug "响应: ${body:0:300}"
            failed=$((failed + 1))
        fi
    done
    
    log_success "上传完成: ${uploaded} 成功, ${failed} 失败"
}

verify_release() {
    echo ""
    log_info "步骤 6/6: 验证 Release"
    
    if response=$(api_get "/repos/${REPO_PATH}/releases/tags/${TAG_NAME}"); then
        log_success "验证成功"
        log_info "标签: ${TAG_NAME}"
        log_info "访问地址: https://gitcode.com/${REPO_PATH}/releases/tag/${TAG_NAME}"
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
    echo "分支: ${BRANCH}"
    
    check_token
    ensure_repository
    ensure_branch
    cleanup_old_tags
    create_release
    upload_files
    verify_release
    
    echo ""
    log_success "🎉 发布完成"
    echo ""
    echo "访问: https://gitcode.com/${REPO_PATH}/releases/tag/${TAG_NAME}"
    echo ""
}

main "$@"
