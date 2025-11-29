#!/bin/bash
# 删除仓库脚本 - 支持 GitCode/Gitee/GitLab

PLATFORM="${1:-$PLATFORM}"

case "$PLATFORM" in
  gitcode)
    API="https://api.gitcode.com/api/v5/repos/${USERNAME}/${REPO_NAME}?access_token=${GITCODE_TOKEN}"
    ;;
  gitee)
    API="https://gitee.com/api/v5/repos/${USERNAME}/${REPO_NAME}?access_token=${GITEE_TOKEN}"
    ;;
  gitlab)
    API="https://gitlab.com/api/v4/projects/${USERNAME}%2F${REPO_NAME}"
    TOKEN="$GITLAB_TOKEN"
    ;;
  *)
    echo "❌ 未知平台: $PLATFORM" && exit 1
    ;;
esac

echo "🗑️ 删除仓库: $PLATFORM - ${USERNAME}/${REPO_NAME}"

if [ "$PLATFORM" = "gitlab" ]; then
  RESP=$(curl -s -w "\n%{http_code}" -X DELETE "$API" -H "PRIVATE-TOKEN: $TOKEN")
else
  RESP=$(curl -s -w "\n%{http_code}" -X DELETE "$API")
fi

HTTP_CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')

if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "202" ]; then
  echo "✅ 删除成功"
elif [ "$HTTP_CODE" = "404" ]; then
  echo "⚠️ 仓库不存在"
else
  echo "❌ 删除失败 (HTTP $HTTP_CODE): $BODY" && exit 1
fi
