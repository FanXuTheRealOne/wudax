# WUDAX 密钥与提交安全规则

本文件是所有人类开发者和 Agent 的强制规则。任何提交前都必须按本文件检查。

## 绝对禁止

- 禁止提交真实 API key、token、secret、私钥、session cookie、OAuth token、Bearer token、Webhook secret、云服务访问密钥。
- 禁止把密钥写进源码、脚本、Markdown、测试、fixture、plist、pbxproj、截图说明、日志或注释。
- 禁止在回复、commit message、PR 描述或 issue 中复述密钥原文。
- 禁止把 `.env`、`.env.local`、临时 key 文件、下载凭证或本地工作区密钥加入 Git。

## 必须使用的方式

需要调用外部服务时，只能通过以下方式注入密钥：

- 本机环境变量，例如：

  ```bash
  export MESHY_API_KEY="..."
  export TOKENROUTER_API_KEY="..."
  ```

- 本机 `.env` 文件。`.env` 已被 `.gitignore` 忽略。
- CI / GitHub Actions secrets。
- macOS Keychain 或其他系统级 secret store。

脚本必须在缺少环境变量时直接失败，并给出不包含密钥的错误提示。

## 当前脚本约定

- `scripts/gen_3d.py` 读取 `MESHY_API_KEY`
- `scripts/gen_ui.py` 读取 `TOKENROUTER_API_KEY`
- `scripts/rodin_bang.py` 读取 `HYPER3D_API_KEY`，并在保存返回结果前脱敏 `subscription_key`
- `.env.example` 只能包含变量名，不能包含真实值

Rodin / Hyper3D 的任务返回可能包含订阅元数据。`assets/3d/bang/*.json` 默认不入库；如果确实需要提交生成结果，只提交最终模型文件，不提交原始 API 响应。

## 提交前必跑扫描

最少执行：

```bash
git diff --check
git grep -n -I -E 'API[_-]?KEY|SECRET|TOKEN|sk-|AIza|github_pat|ghp_|hf_|xox[baprs]-|AWS_ACCESS_KEY|msy_' -- . ':(exclude)WudaX/build' ':(exclude).venv' ':(exclude)WudaX/BundledModel'
```

如果安装了专用工具，优先再跑：

```bash
gitleaks detect --source . --no-git
gitleaks detect --source .
```

没有安装 gitleaks 时，不得以此为理由跳过基础扫描。

## Agent 工作要求

Agent 在准备 commit / push 前必须：

1. 查看 `git status --short`，确认即将提交的文件范围。
2. 运行上面的基础 secret scan。
3. 如果发现疑似密钥：
   - 立即停止提交；
   - 不输出密钥原文；
   - 报告路径、行号、类型和哈希指纹；
   - 清理当前文件；
   - 建议用户 revoke / rotate 已暴露密钥。
4. 只有扫描无命中，才允许继续提交。

## 已泄露密钥的处理原则

一旦密钥进入 Git 历史或公开仓库，必须视为已经泄露：

- 立即 revoke / rotate；
- 删除当前文件里的密钥；
- 必要时重写 Git 历史并 force push；
- 通知所有协作者重新 clone 或清理旧历史。

重写历史不能让旧密钥重新安全；撤销密钥才是第一优先级。
