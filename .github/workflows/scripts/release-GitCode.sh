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

api_patch() {
    local endpoint="$1"
    local data="$2"
    local url="${API_BASE}${endpoint}"
    [ "$url" == *"?"* ] && url="${url}&access_token=${GITCODE_TOKEN}" || url="${url}?access_token=${GITCODE_TOKEN}"
    
    response=$(curl -s -w "\n%{http_code}" -X PATCH \
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

# 使用官方文件上传接口
upload_file() {
    local file="$1"
    local filename=$(basename "$file")
    
    log_info "上传文件: $filename"
    
    # 官方上传接口
    local url="${API_BASE}/repos/${USERNAME}/${REPO_NAME}/file/upload?access_token=${GITCODE_TOKEN}"
    
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -F "file=@${file}" \
        "$url")
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    log_debug "HTTP Code: $http_code"
    log_debug "Response: ${body:0:300}"
    
    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
        # 提取返回的路径
        if command -v jq &> /dev/null; then
            file_path=$(echo "$body" | jq -r '.path // .full_path // empty')
        else
            file_path=$(echo "$body" | grep -o '"path":"[^"]*"' | head -1 | cut -d'"' -f4)
            [ -z "$file_path" ] && file_path=$(echo "$body" | grep -o '"full_path":"[^"]*"' | head -1 | cut -d'"' -f4)
        fi
        
        if [ -n "$file_path" ]; then
            log_success "上传成功: $file_path"
            echo "$file_path"
            return 0
        else
            log_success "上传成功（未获取到路径）"
            return 0
        fi
    else
        log_error "上传失败"
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
}

ensure_repository() {
    echo ""
    log_info "步骤 1/5: 检查仓库 ${REPO_PATH}"
    
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
    log_info "步骤 2/5: 检查分支 ${BRANCH}"
    
    if response=$(api_get "/repos/${REPO_PATH}/branches/${BRANCH}"); then
        log_success "分支已存在"
        return 0
    fi
    
    log_warning "分支不存在，创建中..."
    
    if [ -f ".git/shallow" ]; then
        git fetch --unshallow || { rm -rf .git; git init; }
    fi
    
    [ ! -d ".git" ] && git init
    
    git config user.name "GitCode Bot"
    git config user.email "bot@gitcode.com"
    
    if [ ! -f "README.md" ]; then
        echo "# ${REPO_NAME}" > README.md
        echo "" >> README.md
        echo "${REPO_DESC}" >> README.md
    fi
    
    git add -A
    git diff --cached --quiet && git commit --allow-empty -m "Initial commit" || git commit -m "Initial commit"
    
    local git_url="https://oauth2:${GITCODE_TOKEN}@gitcode.com/${REPO_PATH}.git"
    
    if git remote get-url gitcode &>/dev/null; then
        git remote set-url gitcode "$git_url"
    else
        git remote add gitcode "$git_url"
    fi
    
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
    
    if ! response=$(api_get "/repos/${REPO_PATH}/tags"); then
        log_info "没有现有标签"
        return 0
    fi
    
    tags=$(echo "$response" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | grep -v "^$")
    
    if [ -z "$tags" ]; then
        log_info "没有现有标签"
        return 0
    fi
    
    deleted=0
    while IFS= read -r tag; do
        [ -z "$tag" ] || [ "$tag" = "$TAG_NAME" ] && continue
        
        log_warning "删除标签: $tag"
        
        if api_delete "/repos/${REPO_PATH}/tags/${tag}"; then
            log_success "删除成功"
            deleted=$((deleted + 1))
        fi
        
        sleep 1
    done <<< "$tags"
    
    [ $deleted -gt 0 ] && log_info "已删除 ${deleted} 个旧标签"
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
        log_error "Release 创建失败"
        exit 1
    fi
    
    if echo "$response" | grep -q "\"tag_name\":\"${TAG_NAME}\""; then
        log_success "Release 创建成功"
    else
        log_error "Release 创建失败"
        exit 1
    fi
}

upload_files() {
    echo ""
    log_info "步骤 5/5: 上传文件"
    
    if [ -z "$UPLOAD_FILES" ]; then
        log_info "没有文件需要上传"
        return 0
    fi
    
    uploaded=0
    failed=0
    file_links=""
    
    IFS=' ' read -ra FILES <<< "$UPLOAD_FILES"
    total=${#FILES[@]}
    
    for file in "${FILES[@]}"; do
        [ -z "$file" ] && continue
        
        if [ ! -f "$file" ]; then
            log_warning "文件不存在: $file"
            failed=$((failed + 1))
            continue
        fi
        
        # 检查文件大小（限制20M）
        file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
        file_size_mb=$((file_size / 1024 / 1024))
        
        if [ $file_size_mb -gt 20 ]; then
            log_warning "文件超过20M限制: $file ($file_size_mb MB)"
            failed=$((failed + 1))
            continue
        fi
        
        size=$(du -h "$file" | cut -f1)
        filename=$(basename "$file")
        
        echo ""
        log_info "[$(( uploaded + failed + 1 ))/${total}] $filename ($size)"
        
        if file_path=$(upload_file "$file"); then
            uploaded=$((uploaded + 1))
            
            # 构建文件链接
            if [ -n "$file_path" ]; then
                file_url="https://gitcode.com/${REPO_PATH}/blob/${BRANCH}/${file_path}"
                file_links="${file_links}\n- [${filename}](${file_url})"
            fi
        else
            failed=$((failed + 1))
        fi
    done
    
    echo ""
    log_success "上传完成: ${uploaded} 成功, ${failed} 失败"
    
    # 更新 Release 描述，添加文件链接
    if [ $uploaded -gt 0 ] && [ -n "$file_links" ]; then
        echo ""
        log_info "更新 Release 描述，添加文件链接..."
        
        new_body="${RELEASE_BODY}\n\n## 📦 发布文件${file_links}"
        new_body_escaped=$(echo -e "$new_body" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')
        
        if update_response=$(api_patch "/repos/${REPO_PATH}/releases/${TAG_NAME}" "{\"body\": \"${new_body_escaped}\"}"); then
            log_success "Release 描述已更新"
        else
            log_warning "Release 描述更新失败"
        fi
    fi
}

verify_release() {
    echo ""
    log_info "验证 Release"
    
    if api_get "/repos/${REPO_PATH}/releases/tags/${TAG_NAME}" >/dev/null; then
        log_success "Release 验证成功"
    else
        log_error "Release 验证失败"
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
    log_success "🎉 Release 创建完成"
    echo ""
    echo "访问地址:"
    echo "  https://gitcode.com/${REPO_PATH}/releases"
    echo ""
}

main "$@"
