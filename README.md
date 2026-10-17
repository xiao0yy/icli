# icli

**Apple Calendar, from your terminal.**

`icli` 是一个 macOS 命令行工具。通过 `icli cal` 查看日程、管理事件和日历，支持提醒、重复日程，以及面向脚本和 AI 的 JSON 输出。

[安装](#安装) · [快速开始](#快速开始) · [命令](#命令) · [使用示例](#使用示例)

## 特性

- **系统日历** — 使用 Mac 已同步的 iCloud、Google 等日历。
- **日程管理** — 查询、搜索、创建、修改和删除事件，支持全天日程。
- **提醒与重复** — 多个提醒，日/周/月/年重复，按发生次数或日期结束。
- **日历与筛选** — 管理日历，按日历、参会人筛选，排序和限制结果数量。
- **自动化** — JSON 输出；使用 `--dry-run` 预览变更。

## 安装

需要 **macOS 14+**。从项目的 **Releases** 页面下载对应版本：

| 架构 | 文件 |
| --- | --- |
| Apple Silicon | `icli-v0.2.0-macos-arm64.tar.gz` |
| Intel | `icli-v0.2.0-macos-x86_64.tar.gz` |

以 Apple Silicon 为例：

```sh
tar -xzf icli-v0.2.0-macos-arm64.tar.gz
mkdir -p ~/.local/bin
install -m 755 icli ~/.local/bin/icli
export PATH="$HOME/.local/bin:$PATH"
```

将 `~/.local/bin` 加入 shell 的 PATH 后，申请日历访问权限：

```sh
icli cal auth request
```

> 首次使用需要 macOS 日历授权。当前二进制尚未进行 Apple 公证。

## 快速开始

```sh
# 今天的日程
icli cal today

# 接下来两周
icli cal upcoming -d 14

# 搜索事件
icli cal search '项目讨论'

# 创建事件，提前 15 分钟提醒
icli cal add '项目讨论' \
  -s '2026-10-14T10:00:00+08:00' -e '2026-10-14T10:30:00+08:00' \
  --alert 15m

# 使用查询结果中的事件 ID
icli cal show '<event-id>'
icli cal update '<event-id>' --title '方案讨论'
icli cal delete '<event-id>'

# JSON 输出
icli cal today --json
```

## 命令

| 命令 | 说明 |
| --- | --- |
| `cal today` | 今天的日程 |
| `cal upcoming` | 接下来 N 天的日程，默认 7 天 |
| `cal list` | 按时间范围查询事件 |
| `cal search QUERY` | 搜索标题、地点和备注 |
| `cal show ID` | 查看事件详情 |
| `cal add TITLE` | 创建事件 |
| `cal update ID` | 修改事件 |
| `cal delete ID` | 删除事件 |
| `cal calendars` | 列出日历 |
| `cal calendars create/update/delete` | 创建、修改或删除日历 |
| `cal sources` | 列出日历账户 |
| `cal auth status/request` | 查询或申请权限 |

使用 `icli cal <command> --help` 查看完整选项。

## 使用示例

### 筛选日程

```sh
# 指定日期范围
icli cal list -f 2026-10-01 -t 2026-11-01

# 多日历查询，排除节假日日历
icli cal upcoming -c '工作' -c '个人' --exclude-calendar '节假日'

# 按参会人筛选，隐藏重复事件
icli cal upcoming --attendee alice --no-recurring

# 排序并限制结果数量
icli cal upcoming --sort title -n 10
```

### 全天事件与提醒

```sh
# 一天的全天事件：结束日期不包含
icli cal add '休假' --all-day -s 2026-10-14 -e 2026-10-15

# 替换提醒：提前 1 小时和 15 分钟
icli cal update '<event-id>' --alert 1h --alert 15m

# 清空提醒
icli cal update '<event-id>' --no-alert
```

### 重复日程

```sh
# 每周重复，共 8 次
icli cal add '每周例会' \
  -s '2026-10-14T10:00:00+08:00' -e '2026-10-14T10:30:00+08:00' \
  --timezone Asia/Shanghai --repeat weekly --repeat-count 8

# 修改本次、未来或整个系列分支
icli cal update '<occurrence-id>' --title '临时调整' --scope this
icli cal update '<occurrence-id>' --title '后续例会' --scope future
icli cal update '<occurrence-id>' --repeat monthly --repeat-count 6 --scope all
```

重复事件的修改和删除需要显式指定 `--scope this|future|all`。`all` 作用于当前系列分支；拆分过的历史分支分别处理。系列变更后请重新查询发生项 ID。

### 日历管理

```sh
icli cal sources
icli cal calendars create '项目' --source '<source-id>' --color '#42D692'
icli cal calendars update '<calendar-id>' --title '归档' --color '#AABBCC'
icli cal calendars delete '<calendar-id>' --dry-run
```

### 预览与脚本

```sh
icli cal update '<event-id>' --title '方案讨论' --dry-run --json
icli cal delete '<event-id>' --dry-run
icli cal today --json | jq '.data[].title'
```

`--dry-run` 不保存变更。删除默认要求确认，脚本可使用 `--yes`；删除日历会同时删除其中的事件。

时间输入支持带偏移的 ISO 8601，或本地时间搭配 `--timezone`；自由表达式如 `tomorrow 9am` 暂未支持。含参会人的邀请事件目前只读。
