# 路由器后台操作通用方法

> SKILL.md 的补充参考。只在需要定位页面、读表、填表时读。
> 各家 Web 管理页 UI 差异大、字段 id 随固件变化，本文件给的是**通用定位方法与字段语义**，不绑定任何具体型号。

## 一、通用定位思路

路由器管理页基本都是 SPA。定位方式优先级：

1. **先看页面文字**，用 `document.body.innerText` 找菜单名，胜过猜 class。
2. 表格内容用 `innerText` 按块读，**不要用 `tr.textContent`**——相邻单元格文本会粘连（`WAN`+`80`+`80` 会拼成 `WAN8080`），必须逐单元格读。
3. 表单里区分「可见输入框」和「隐藏 input」：下拉框通常有一个 `hidden` 的 value input，**只改它的 value 不会通过校验**。
4. 下拉框必须**真正点选选项**，并以「校验错误提示消失」为通过判据。

## 二、菜单名与表单字段语义

### 菜单名

同一个功能在不同品牌/型号下叫法不同，按语义找即可：

| 语义 | 常见叫法 |
|---|---|
| 端口映射 | 虚拟服务器 / 端口映射 / 端口转发 / 端口规则 / NAT 服务 / 应用程序 |
| 路由器自身管理页 | 管理地址 / 系统管理设置 / 网络设置 |

### 表单字段语义

不管叫法怎么变，一条规则永远由这几项组成：

| 语义 | 常见叫法 | 填什么 |
|---|---|---|
| 规则名 | 服务名 / 规则名 / 描述 | 自定义，便于后续辨认 |
| 生效接口 | 生效接口 / WAN 接口 / 应用接口 | **必须选外网那一侧**（WAN / Internet / 互联网） |
| 外部端口 | 外部端口 / 起始端口 / 源端口 | 公网侧端口（与「下一跳的外部端口」保持一致） |
| 内部端口 | 内部端口 / 目的端口 / 结束端口 | **等于下一跳的外部端口**，不是最终服务的端口 |
| 内部主机 | 内部服务器 IP / 内部主机 / 目标 IP | **下一层设备的 WAN 口 IP** |
| 协议 | 服务协议 / 协议 | TCP / UDP / 两者 / ALL |

## 三、通用坑

### 生效接口必须真点选

只改隐藏 input 的 value 不会触发校验与提交。通用做法（选择器需按实际页面调整）：

```javascript
// 展开下拉：点开下拉容器上的展开控件
document.querySelector('.combobox-container .combobox-switch').click();
// 真实点选可见选项，而不是直接改隐藏 input
document.querySelector('label.combobox-label').click();
// 校验通过的判据：页面上不再有校验错误标记
document.querySelectorAll('.widget-container.error').length === 0
```

失败表现：表格出现 `--` 空行，或整行字段为空。

### 改 DOM 不等于提交

部分 SPA 把表单值存在框架内部状态里，直接给 input 赋值再点保存，提交上去的是空值。通用处理：

1. 赋值后派发 `input` / `change` 事件，让框架感知。
2. 保存后**回读表格该行**核对每个字段。
3. 若表格里是空值或旧值，说明框架状态没被更新——此时才需要去翻框架实例（Vue 看 `__vue__`、React 看 `__reactFiber$`）直接改状态。

### 表格分页

规则多时表格会分页。翻页控件在表格下方的分页容器里，翻页按钮类名与"当前页"高亮类名常常只差大小写或前缀（`.ListSpan` vs `.listSpanS` 这类）。读取全部规则前记得逐页翻。

### 「设备」列显示成本机名

内部主机没真实填下一层 WAN IP 时，设备列会显示当前 PC 的主机名或空白。保存后必须核对这一列。

### 内部端口填错会静默失败

中间层的内部端口必须等于**下一跳的外部端口**（通常同名）。填成最终服务的端口时，外网表现为超时而不是报错，最难排查。

### 保存后核对绑定

部分实现会把"内部主机"绑到 MAC 而不是 IP。保存后核对内部主机标识是否指向下一层设备的 WAN 口，必要时手动改成正确值再保存一次。

### 会话超时

部分管理页有较短会话空闲超时。批量操作前先确认超时时长，操作尽量连续，超时后重新登录。

## 四、服务器侧 nginx 配套改动（宝塔）

映射到某端口后，服务器 nginx 站点需要能服务该端口。

### 站点 vhost

`/www/server/panel/vhost/nginx/<站点>.conf`

```nginx
listen <内部端口>;
server_name <域名>;
```

需要 TLS 时：

```nginx
listen <内部端口> ssl;
ssl_certificate     /www/server/panel/vhost/cert/<站点>/fullchain.pem;
ssl_certificate_key /www/server/panel/vhost/cert/<站点>/privkey.pem;
```

**必须删除**（若存在）：

```nginx
error_page 497  https://$host$request_uri;
```

原因：497 = 明文请求打到 SSL 端口，该行 301 到不带端口的 443；443 常被运营商封禁 → HTTP 也打不开。

### 伪静态 / API 反代

宝塔「网站 → 伪静态」管理的文件位于：

```
/www/server/panel/vhost/rewrite/<站点>.conf
```

由站点 vhost 的 `#REWRITE-START` 段 include：

```nginx
include /www/server/panel/vhost/rewrite/<站点>.conf;
```

**注意路径层级**：是 `vhost/rewrite/`，**不是** `vhost/nginx/rewrite/`。写错会报 `emerg: open() ... No such file or directory`。

常见内容（SPA 回退 + 后端反代）：

```nginx
location / { try_files $uri $uri/ /index.html; }
location ^~ /api/  { proxy_pass http://127.0.0.1:<后端端口>/api/;  ... }
location ^~ /auth/ { proxy_pass http://127.0.0.1:<后端端口>/auth/; ... }
location ^~ /ws/   { proxy_pass http://127.0.0.1:<后端端口>/ws/;   ... }
```

### 后端不需要配 SSL

TLS 在 nginx 终结，nginx 到 `127.0.0.1:<后端端口>` 是同机明文回环。`proxy_pass` 保持 `http://` 即可。

### 改完执行

```bash
/www/server/nginx/sbin/nginx -t && /www/server/nginx/sbin/nginx -s reload
```

> 面板重新部署/续期证书会重写 vhost，改完需复核。
