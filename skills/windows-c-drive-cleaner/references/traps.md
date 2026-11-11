# 删前必查陷阱清单

每条 = 现象 → 为什么 → 怎么查/怎么做。扫描报告 Guard 列引用的编号就是这里的编号。

## 1. JetBrains LocalHistory 绝不删
- **现象**：`%LOCALAPPDATA%\JetBrains\<product>\LocalHistory`（2020.1+ 版本布局）可能几百 MB，看起来和缓存没区别。
- **为什么**：它是 IDE 的本地历史（相当于本地时间机器），删了无法恢复，用户改丢代码会当场爆炸。
- **怎么做**：清理脚本已把名为 `LocalHistory` 的目录列入硬保护（含子树内检测），参数覆盖不了。手工清理时同样跳过；只删 `<product>` 旧版本目录。

    10|## 2. 插件 zip 删前验 Roaming 副本
- **现象**：下载目录/备份目录里的 PhpStorm/JetBrains 插件 zip，看似重复。
- **为什么**：Roaming 里没有对应副本时，zip 就是唯一安装源，删了要重新找版本。
- **怎么做**：删 zip 前在 `%APPDATA%\JetBrains\<product>\plugins`（或对应插件目录）确认同名插件已安装；没有副本就保留。

## 3. 包缓存删前查版本 pin
- **现象**：`.gradle\caches`、`.m2\repository`、`ms-playwright` 都是"可再生"缓存，动辄几个 GB。
- **为什么**：项目 pin 了特定版本（Gradle wrapper、Playwright browser build）时，删了会触发重新下载几百 MB～几 GB，离线/弱网环境直接把构建搞挂。
- **怎么做**：Gradle 看 `gradle/wrapper/gradle-wrapper.properties`；Playwright 看项目 `package.json` 的 browser version 或直接确认能联网重下；Maven 看是否有离线 mirror 约定。pin 存在且要离线 → 保留或只清旧版本。

    20|## 4. VS Installer BackgroundDownload 会伪装成"垃圾"
- **现象**：`%TEMP%` 下随机名目录各占几 GB（如 `obdifws5`），没有 VS 进程在跑。
- **为什么**：VS Installer 的用户态 bootstrapper（`Microsoft.VisualStudio.Setup.Service\BackgroundDownload.exe`）会在等更新时后台预下载约 5G 到 `%TEMP%` 随机目录；**判活不能靠查进程名**，bootstrapper 是服务方式存在，间歇性醒来。
- **怎么做**：看 `%TEMP%\dd_BackgroundDownload_*.log` 的最新 mtime；48h 内有写入 → 别动随机名大目录。VS 已卸载 + 2 天写静默 → 才算安全。

## 5. Package Cache 的"孤儿判断"不可信
- **现象**：`C:\ProgramData\Package Cache` 几个 GB，脚本/网文教你按 GUID 对比 Uninstall 表找孤儿。
- **为什么**：Burn 缓存目录的 GUID 和"卸载"注册表键的 GUID 不是一回事，实测会 343/343 全判孤儿（连 .NET SDK 都"孤儿"）。
- **怎么做**：唯一可靠路径 = 内容身份判定（payload 路径还存在吗）→ **可逆 move 出去** → 跑一次相关工具链构建验证 → 再删。另外先确认工具链是否还需要：MSVC 链接要 SDK 的 `.lib`，查 `reg query "HKLM\SOFTWARE\Microsoft\Windows Kits\Installed Roots"` 和工程类型（SDK-style 工程 WinRT 依赖走 NuGet，可不需要本机 SDK；旧式 .NET Framework 工程需要 targeting pack）。

    30|## 6. pagefile.sys / hiberfil.sys 不是垃圾
- **现象**：C 盘根 `pagefile.sys` 十几 GB 且大小会自己变，`df`/可用空间跟着跳。
- **为什么**：虚拟内存页面文件 + 休眠文件，系统自管。删了轻则蓝屏配置错乱，重则当前会话崩。
- **怎么做**：只解释，不删。真要回收：`powercfg /h off`（关休眠，T3 级决定）或把页面文件挪到别的盘（改系统设置，重启生效）。

## 7. NTFS junction 会双计甚至死循环
- **现象**：用户目录下 `Application Data`、`Local Settings`、`My Documents` 是指向自身的 junction，扫描工具要么报天文数字要么卡死。
- **为什么**：向后兼容的 reparse point；`du`/朴素递归会把同一份算 N 遍，还可能无限递归。
- **怎么做**：扫描脚本已跳过 ReparsePoint 属性的目录。手工扫描用 `[System.IO.File]::GetAttributes() -band ReparsePoint` 判断；报告里注明"已排除 junction"。

    40|## 8. Git Bash `du` 在 AppData 必超时
- **为什么**：MSYS 单线程 stat 十万级小文件 + 中文路径，跑不完 120s。
- **怎么做**：用本技能的 PS 脚本（runspace 并行 + 单目录 deadline + 超时标"≥"）。PS 5.1 没有 `-Parallel`，别白试；自己写也要走 runspace pool。

## 9. 保护性删除禁用 `find ! -name` 白名单
- **现象**：`find . -maxdepth 1 ! -name '保留名' -delete` 想留几个删其余，结果**连保留项一起删了**（中文名/编码不一致时静默不匹配），`rm` 又不进回收站。
- **怎么做**：先把要保留的 `mv` 到 ASCII 暂存目录 → 删原目录 → 把保留项 `mv` 回来 → `ls` 核对数量和名字。清理脚本的 Staging 模式就是这套逻辑的工程化。

## 10. 删除一律回收站优先
- **为什么**：`rm`/`Remove-Item` 不进回收站；回收站便宜，后悔药贵。
    50|- **怎么做**：脚本 `-Mode Recycle`（Microsoft.VisualBasic `SendToRecycleBin`）。只有回收站装不下/用户明确要求时才 `Delete`，且大目录先 Staging。

## 11. dev server 起不来先查保留端口段
- **现象**：vite/node 绑定端口报 `EACCES`，像权限问题，其实和缓存无关。
- **为什么**：Hyper-V/WSL 会保留大段 TCP 端口（如 5087–5186）。
- **怎么做**：`netsh interface ipv4 show excludedportrange protocol=tcp`，换段外端口。列在这里是为了别把端口问题误判成"清理没做完"。

## 12. 0.00GB ≠ 空目录
- **现象**：扫描结果里某目录 0.00GB / 0 files，但 df 显示空间确实被吃了。
- **为什么**：权限拒绝、扫描超时、junction 被跳过、稀疏文件按 apparent size 计，都会造成"看起来是零"。
    60|- **怎么做**：状态列有 `timed-out` / Errors 的行，大小只能当地板；怀疑时用管理员重扫该目录。报告一律写"≥"。

## 13. 往 .ps1/.bat 里写中文 = 脚本错位执行
- **现象**：脚本"没跑"，控制台吐一堆「不是内部或外部命令」，没有指向编码的报错。
- **为什么**：zh-CN 系统 cmd/PS 5.1 按 GBK 读 UTF-8 文件，字节错位后 REM 注释的碎片被当命令执行。
- **怎么做**：技能内脚本已全 ASCII。自己临时写脚本也保持 ASCII；给用户的报告用中文在会话里写，不进脚本。

    70|## 14. IDE 扩展目录的 GUID 残留目录 = 安装中断的垃圾
- **现象**：`%USERPROFILE%\.vscode\extensions\` 下出现 `.c2458e54-83a5-4390-a748-7d7bf8222d14` 这类 GUID 命名的目录，单个几百 MB 到 1.3 GB。
- **为什么**：VS Code 扩展安装走"下载到临时目录再重命名"的流程，中断/被杀就会留下 GUID 目录。它们**不是有效扩展**，但占空间巨大，且不会被 VS Code 清理。
- **怎么做**：目录名匹配 `^\.[0-9a-f]{8}-[0-9a-f]{4}-` 且 LastWriteTime 超过几天 → 可删。同时检查同一扩展的多个版本目录（如 `anthropic.claude-code-2.1.301` 与 `2.1.314`），只保留最新版本。

## 15. `CachedExtensionVSIXs` 是纯安装包垃圾
- **现象**：`%APPDATA%\Code\CachedExtensionVSIXs` 几个 GB，里面是一堆 `.vsix` 文件。
- **为什么**：这是 VS Code 缓存的扩展安装包，装完就没用了。它和 `%USERPROFILE%\.vscode\extensions` 里已安装的扩展是重复内容。
- **怎么做**：可整目录删。但注意 `CachedExtensionVSIXs` 在 **Roaming** 而非 Local，别找错路径。

## 16. 应用自动更新包目录（`*-updater`）是安全垃圾
- **现象**：`%LOCALAPPDATA%` 下几十个 `@xxx-updater`、`xxx-updater` 目录，每个 100-700 MB，累计好几个 GB。
- **为什么**：Electron 应用的自动更新包下载后解压留存在这里，更新完不清理。目录名以 `-updater` 结尾是明确特征。
- **怎么做**：扫描时用 `-updater$` 模式批量识别。**注意排除** `ProgramData` 下的同名目录（可能是驱动组件），只清 `%LOCALAPPDATA%`。

## 17. `ProgramData\NVIDIA\NGX` 不是垃圾，是 DLSS 模型
- **现象**：`C:\ProgramData\NVIDIA\NGX` 1.4 GB，看着像显卡驱动残留。
- **为什么**：这是 **DLSS 神经超分辨率模型文件**，删掉会让支持 DLSS 的游戏/应用降级或黑屏。名字里有 "NGX"（NVIDIA Extended Graphics）但和驱动安装包无关。
- **怎么做**：`NGX` 必须保留。可删的是同级的驱动安装包残留：`ProgramData\NVIDIA Corporation\Nsight\*`（安装包）、`NVIDIA App` 缓存、`ShadowPlay` 旧日志、`Drs` 等。

    80|## 18. 浏览器 Service Worker 缓存是隐形大户
- **现象**：`%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Service Worker` 6+ GB，比 `Cache` 目录大两个数量级。
- **为什么**：Service Worker 存的是站点离线数据/PWA 缓存，很多用户从不清。`Cache`/`Code Cache` 往往只有几十 MB，扫了会以为浏览器没占空间。
- **怎么做**：单独列为 T2 目标。**必须先完全关闭浏览器进程**（约 25-30 个 msedge 进程），否则文件被锁删不掉。

## 19. Yarn Berry 的缓存路径不是 `Yarn\Cache`
- **现象**：扫描 `%LOCALAPPDATA%\Yarn\Cache` 什么都没找到，但 `Yarn` 目录占 2.5 GB。
- **为什么**：Yarn 2+ (Berry) 的缓存路径是 `%LOCALAPPDATA%\Yarn\Berry\cache`（小写 c），旧版 Yarn 1 才是 `Yarn\Cache`（大写 C）。
- **怎么做**：两个路径都扫。Windows 文件系统大小写不敏感，但目录结构不同，别只测一个。

## 20. 清 Temp 时别把自己脚下的脚本删了
- **现象**：执行清理 `%TEMP%` 的脚本中途报错「xxx.ps1 不是内部或外部命令」，脚本"半途而废"。
- **为什么**：PowerShell 会把当前运行的临时脚本写到 `%TEMP%\ps-script-<guid>.ps1`。清空 Temp 时把自己的脚本删了，后续命令就执行不了。
- **怎么做**：清 Temp 时用 `-Exclude` 排除 `ps-script-*`，或先算出脚本自身路径再跳过。

## 21. 删完可用空间可能反降 —— 别急着怀疑自己删错了
- **现象**：清理后可用空间短暂上升，随后又掉下去几 GB。
- **为什么**：`pagefile.sys` 会随内存压力自行扩张（16 GB 内存机器上能到 24 GB），加上系统临时分配。这不是回滚。
- **怎么做**：用**同一个口径**复核：顶层目录总大小对比 + 关键目录逐个量 + root 文件（`pagefile`/`hiberfil`）大小对比。只要目标目录确实变小，就是清理成功。汇报时给出净差值，不要只报峰值。

## 22. 跑在后台的扫描结果要会"回收"
- **现象**：大目录扫描（`C:\Users`、`C:\Windows`）常超过 240s 前台超时，被转后台；结果写在终端输出文件里，不主动去看就以为没结果。
- **怎么做**：长扫描统一放后台并显式等待（`Start-Sleep` + 读输出文件），不要用前台 `block_until_ms` 硬等。

## 23. nvm 多版本目录要按"当前使用"判断
- **现象**：`%LOCALAPPDATA%\nvm` 几个 GB，里面是 `v20.x`/`v24.x`/`v25.x` 各一份。
- **为什么**：`nvm list` 里带 `*` 的才是当前版本。删掉当前版本会让 `node` 直接不可用。
- **怎么做**：`nvm list` 确认当前版本 → 只删未使用的老版本。留着至少一个 LTS 备用。

## 24. `codex-runtimes` 里 `.previous-*` 是历史快照
- **现象**：`%USERPROFILE%\.cache\codex-runtimes` 1.5+ GB，里面是 `codex-primary-runtime` 加若干 `codex-primary-runtime.previous-<guid>` 目录。
- **为什么**：每次 codex 更新运行时，旧版本被重命名保留成 `.previous-<guid>`。它们不再被使用，但没人清理，累积起来很可观。
- **怎么做**：删 `codex-primary-runtime.previous-*`，**保留**不带 `.previous-` 的那个。这是模式目标（pattern target）的典型场景：根目录不能删，只删匹配的子目录。

## 25. AVD 模拟器每个 4-6 GB，看修改时间再决定
- **现象**：`%USERPROFILE%\.android\avd` 下每个 `.avd` 目录 4-6 GB，三个就是 14 GB。
- **为什么**：模拟器镜像和快照。只看"哪个大"会误删正在用的那个。
- **怎么做**：看每个 `.avd` 的 `LastWriteTime` —— 今天还在改的就是在用。`%USERPROFILE%\.android` 下的 `adbkey`、`debug.keystore` 更是不能碰。整目录属 T3，必须逐项点头。

## 26. PSCustomObject 不能事后加属性
- **现象**：脚本里 `$obj.IsPattern = $true` 报「在此对象上找不到属性"IsPattern"」，或者 `Select-Object` 导出后该字段变成 `null`。
- **为什么**：`[pscustomobject]@{}` 创建的是固定形状的对象，PowerShell 不允许运行时追加新属性。漏声明的字段在 `ConvertTo-Json` 后就变成 `null`，下游脚本读到 `null` 就静默跳过，整条链路失效还不报错。
- **怎么做**：所有可能后续用到的字段都在 `[pscustomobject]@{}` 里**提前声明**（含 `$null` / `$false` 占位）。尤其是要导出给 JSON 给别的脚本消费的场景 —— 导出前用 `Select-Object` 显式列出字段，并用 `$t.PSObject.Properties['X']` 判存在而不是直接读值。

