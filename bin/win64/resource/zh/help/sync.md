## 同步和比较

<!--dir-sync-->- **Ctrl+Alt+S** – 同步活动面板和非活动面板的文件夹: 单向或双向; 勾选"仅预演"会显示将要执行的操作,但不做任何更改。
- 在同步对话框中,每个差异是一行列表,带有其操作: `->` 复制到右侧,`<-` 复制到左侧,`--` 跳过; 冲突起初为跳过。"向右"、"向左"和"跳过"按钮设置所选行的操作(手动选择以 `*` 标记),"重置"恢复自动操作,"仅显示已跳过"只显示尚未决定的行。被跳过的差异会保留到下一次同步。
- 比较开始前,会先弹出一个小对话框,显示两个文件夹,并询问模式(单向或双向)、比较方式(日期和大小,或内容)以及要排除的内容:联接点和符号链接(默认跳过)、`.gitignore`、`.geminiignore` 和 `.obsidianignore` 中的规则(子文件夹中的文件只对该文件夹生效)、robocopy 文件 `exclude.rcj` 中的 `/XD` 和 `/XF` 列表、Obsidian 库的忽略过滤器(`.obsidian/app.json`),以及用 `;` 分隔的附加规则。规则遵循 gitignore 语法:`*`、`?`、`**`、`[a-z]`,末尾 `/` 表示文件夹,开头 `/` 表示根目录,`!` 表示重新包含。被排除的文件不会出现在计划中,也不会出现在镜像模式的多余文件里。 如只需同步某些类型的文件,请在“仅限匹配的文件”栏中填写如 `*.md;*.txt` 的名称掩码:其他文件同样被排除,文件夹仍会被遍历。该栏默认为 `*.*`(所有文件),也接受如 `@Video` 的掩码组,并保留掩码历史。
- 比较文件夹时,对话框会显示已扫描的文件和文件夹数量,随后显示已比较的文件数量以及当前路径。按 **Esc** 可把比较转入后台:标签栏和任务列表中保留带进度的标签,完成后变为 **OK**,点击即可打开计划。
- 复选框 **镜像** 还会删除只存在于目标的文件(试运行默认开启,需有意取消);按钮 **多余文件到面板** 会把这些文件放入临时面板,删除前可先查看。命名预设保存模式、比较方式和复选框。
<!--compare-files-->- **Ctrl+Alt+C** – 比较两个面板光标所在的文件，或活动面板中标记的两个文件；对话框显示大小、修改时间和内容比较结果。标记两个或更多文件时，会比较同名文件（两个面板都有标记：只比较已标记的；仅一个面板有标记：按名称在另一面板中查找），列表显示每一对是相同还是不同，按 Enter 打开差异。文件夹会被跳过。
  For text files a compare-and-merge window opens: two columns with line numbers and the differences marked in the middle (`~` changed, `<` only on the left, `>` only on the right). **Ctrl+Down** and **Ctrl+Up** move between differences, **Right** copies a difference from left to right, **Left** from right to left, **Ctrl+Z** undoes a copy, **Ctrl+S** writes the changed files with their original encoding and line breaks. Closing with unsaved changes asks for confirmation (a second close discards them). Binary, very large (over 16 MB or 60000 lines) and identical files are shown in the earlier summary window.
<!--compare-folders-->- **Ctrl+Shift+C** – 比较文件夹: 两个面板会选中对方没有的文件,以及同名文件中较新的一个; 时间相同但大小不同则两边都选中。

比较细节:
- 文件夹只在对方没有时才会被选中。
- 比较的是当前面板列表,不含子文件夹,因此在压缩包和 SFTP 中同样可用。
- 对话框会询问以什么作为差异:时间、大小、内容。
- 内容只对磁盘上大小相同的文件逐字节比较,并在后台进行(Esc 取消)。

---

[目录](index.md)
