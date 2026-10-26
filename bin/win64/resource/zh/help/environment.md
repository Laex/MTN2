## 环境配置文件

**选项 → 环境配置文件...** 在编辑器中打开 `environment.json` 文件(首次使用时会创建并写入一个示例)。配置文件是一份命名的 `NAME=值` 条目列表,会叠加到每个新 shell 的环境上:终端标签页和面板下方的控制台。已在运行的 shell 保持原有环境;保存文件之后启动的 shell 会看到更改。

```json
{
  "profiles": [
    { "name": "default", "vars": ["EDITOR=vim", "WORK=%TEMP%\\work", "OLD_VARIABLE="] },
    { "name": "proxy", "auto": false, "shells": ["pwsh"], "vars": ["HTTPS_PROXY=http://proxy:3128"] }
  ]
}
```

**条目。** 配置文件按文件中的顺序应用,条目按列表顺序应用,因此后面的条目能看到前面条目的结果。值为空的条目(`OLD_VARIABLE=`)会删除该变量。`%NAME%` 在所有系统上都会被替换为变量的当前值;在 Linux 和 macOS 上 `$NAME` 和 `${NAME}` 同样有效。未设置的名称保持原样。在 Windows 上比较名称时不区分大小写。

**哪些配置文件对 shell 生效**
- `default` – 对所有 shell 生效,最先应用。
- `auto`(默认开启)– 配置文件自动生效。设为 `"auto": false` 时,只对指定它的 shell 生效(见下)。
- `shells` – 该配置文件面向的 shell 配置:`pwsh`、`wsl`、`wsl:Ubuntu`,或副本的标识,如 `pwsh#2`。单写 `wsl` 也包括 `wsl:Ubuntu`,基础标识包括它的副本。为空或缺省 – 所有 shell。
- `off` – 设为 `true` 则完全关闭该配置文件,即使有 shell 指定了它。

<!--choice-->**为单个 shell 选择配置文件。** 在 shell 列表(**Ctrl+Shift+N**)中,**F6** 为所选 shell 或其副本打开环境配置文件的选择。这样的 shell 以 `default` 和所选配置文件启动;`(无)` 恢复为自动配置文件。列表中只有未关闭且不叫 `default` 的配置文件。

该文件包含在 **导出设置 / 导入设置** 中。

---

[目录](index.md)
