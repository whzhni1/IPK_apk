
## Fork本项目后需要做些什么？

### 1. 修改工作流文件中的用户名
修改 `.github/workflows/` 目录下的所有工作流文件，将 `whzhni` 替换为你自己的 对应平台的 用户名。

### 2. 注意同步配置
特别注意 `sync-upstream-releases.yml` 文件中的配置：

- {github_owner: "whzhni1", github_repo: "luci-app-tailscale", local_name: "tailscale"}

⚠️ **注意**：`whzhni1` 这个用户名不能修改。

### 3. 注册代码托管平台并配置令牌

#### 3.1 注册平台并创建令牌
注册以下平台并创建访问令牌：
- [gitee](https://gitee.com)
- [gitcode](https://gitcode.com) 
- [gitlab](https://gitlab.com)

在创建令牌时，请勾选所有权限，然后复制令牌备用，- [创建令牌指南](./tokens_README.md)。

#### 3.2 配置 GitHub Secrets
回到 GitHub 仓库，按以下步骤配置：
1. 点击 `Settings` → `Secrets and variables` → `Actions`
2. 点击 `New repository secret`
3. 分别添加以下三个 secret：
   - **Name**: `GITCODE_TOKEN`，**Secret**: 你的 gitcode 访问令牌
   - **Name**: `GITEE_TOKEN`，**Secret**: 你的 gitee 访问令牌  
   - **Name**: `GITLAB_TOKEN`，**Secret**: 你的 gitlab 访问令牌

#### 3.3 测试 Release 工作流
1. 点击 Actions
2. 运行 `Release 脚本` 工作流
3. 在项目名称处填写你 Fork 后的本项目名称
4. 运行工作流，系统将自动在 gitcode、gitee、gitlab 创建对应项目

#### 3.4 同步上游插件
运行 `同步上游发布插件` 工作流，系统将：
- 批量同步多个插件到 gitcode、gitee、gitlab
- 自动创建仓库并发布 Releases

# 过滤规则配置表格

## 过滤规则参数说明

| 参数 | 类型 | 语法 | 默认值 | 必需 |
|------|------|------|--------|------|
| `filter_include` | 包含规则 | `"模式:数量限制 模式:数量限制"` | 无 | ❌ |
| `filter_exclude` | 排除规则 | `"模式1 模式2"` | 无 | ❌ |
| `filter_by_version` | 版本过滤 | `true`/`false` | `false` | ❌ |

## filter_include 包含规则详解

### 基本语法

"模式1:数量限制 模式2:数量限制 模式3:数量限制"


### 配置示例表格

| 配置示例 | 说明 | 匹配文件示例 | 结果 |
|----------|------|--------------|------|
| `"luci-app-*:1"` | 匹配 `luci-app-` 开头的文件，最多保留1个 | `luci-app-openclash.ipk`<br>`luci-app-passwall.ipk` | 只保留第一个匹配的文件 |
| `"luci-i18n-*:2"` | 匹配 `luci-i18n-` 开头的文件，最多保留2个 | `luci-i18n-openclash-zh-cn.ipk`<br>`luci-i18n-openclash-en.ipk`<br>`luci-i18n-openclash-ja.ipk` | 保留前2个匹配的文件 |
| `"*{VERSION}*:1"` | 匹配包含版本号的文件，最多1个 | `openclash-v1.0.0.ipk`<br>`openclash-v1.1.0.ipk` | 保留第一个匹配的文件 |
| `"*.ipk:3 *.tar.gz:1"` | 匹配 `.ipk` 文件最多3个，`.tar.gz` 文件最多1个 | `plugin1.ipk`<br>`plugin2.ipk`<br>`plugin3.ipk`<br>`source.tar.gz` | 保留所有匹配的文件 |

### 特殊变量
- `{VERSION}`: 自动替换为实际版本号（不带 `v` 前缀）
  - 例如：版本 `v1.2.3` → `{VERSION}` 替换为 `1.2.3`

## filter_exclude 排除规则详解

### 基本语法
```
"模式1 模式2 模式3"
```

### 配置示例表格

| 配置示例 | 说明 | 匹配文件示例 | 结果 |
|----------|------|--------------|------|
| `"*.zip"` | 排除所有 `.zip` 文件 | `package.zip`<br>`source.zip`<br>`package.ipk` | 只保留 `.ipk` 文件 |
| `"luci-19.07*"` | 排除 `luci-19.07` 开头的文件 | `luci-19.07-openclash.ipk`<br>`luci-21.02-openclash.ipk` | 保留非 19.07 版本 |
| `"*test* *debug*"` | 排除包含 `test` 或 `debug` 的文件 | `plugin-test.ipk`<br>`debug-package.ipk`<br>`release.ipk` | 只保留 `release.ipk` |
| `"*.zip *.tar.gz"` | 排除压缩包文件 | `package.zip`<br>`source.tar.gz`<br>`plugin.ipk` | 只保留 `.ipk` 文件 |

## filter_by_version 版本过滤

### 配置说明

| 值 | 说明 | 示例文件 | 结果 |
|----|------|----------|------|
| `true` | 只保留包含版本号的文件 | `plugin-v1.0.0.ipk`<br>`plugin.ipk`<br>`readme.md` | 只保留 `plugin-v1.0.0.ipk` |
| `false` | 不过滤版本号（默认） | 所有文件 | 保留所有文件 |

## 实际用例配置表格

### 单个插件配置

| 插件 | 配置示例 | 说明 |
|------|----------|------|
| OpenClash | `{github_owner: "vernesong", github_repo: "OpenClash", local_name: "luci-app-openclash"}` | 无过滤，同步所有文件 |
| Lucky | `{github_owner: "gdy666", github_repo: "luci-app-lucky", local_name: "lucky", filter_include: "luci-app-*:1 luci-i18n-*:1 *{VERSION}*wanji*"}` | 保留 Luci 应用、语言包和特定版本文件 |
| Passwall | `{github_owner: "xiaorouji", github_repo: "openwrt-passwall", local_name: "luci-app-passwall", filter_exclude: "luci-19.07* *.zip"}` | 排除旧版本 Luci 和压缩包 |

### 组合过滤规则

| 场景 | 配置示例 | 效果 |
|------|----------|------|
| 精确控制文件类型 | `filter_include: "luci-app-*:1 luci-i18n-*:2 *.ipk:5"` | 每种类型文件数量限制 |
| 排除不需要的文件类型 | `filter_exclude: "*.zip *.tar.gz *test* *debug*"` | 清理临时文件和测试文件 |
| 版本特定文件 | `filter_include: "*{VERSION}*:1" filter_by_version: true` | 只保留包含版本号的主要文件 |
| 最小化同步 | `filter_include: "luci-app-*:1" filter_exclude: "*.zip"` | 只同步必要的应用文件 |

## 通配符使用指南

| 通配符 | 说明 | 示例 | 匹配 |
|--------|------|------|------|
| `*` | 匹配任意字符 | `luci-*` | `luci-app`、`luci-theme` |
| `?` | 匹配单个字符 | `plugin-?.ipk` | `plugin-1.ipk`、`plugin-a.ipk` |
| `[abc]` | 匹配括号内任意字符 | `plugin-[abc].ipk` | `plugin-a.ipk`、`plugin-b.ipk` |
| `{VERSION}` | 版本号变量 | `*-{VERSION}.ipk` | `plugin-1.2.3.ipk` |

## 最佳实践

1. **数量限制**: 使用 `:数量` 限制避免下载过多文件
2. **版本变量**: 使用 `{VERSION}` 确保匹配正确版本
3. **组合使用**: 先包含后排除，精确控制文件
4. **测试验证**: 先在单个插件测试过滤效果

通过合理配置这些过滤规则，可以精确控制同步的文件内容和数量，避免不必要的带宽和存储消耗。
