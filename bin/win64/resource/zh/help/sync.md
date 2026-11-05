## 同步和比较

<!--dir-sync-->- **Ctrl+Alt+S** – 同步活动面板和非活动面板的文件夹: 单向或双向; 勾选"仅预演"会显示将要执行的操作,但不做任何更改。
- 在同步对话框中,每个差异是一行列表,带有其操作: `->` 复制到右侧,`<-` 复制到左侧,`--` 跳过; 冲突起初为跳过。"向右"、"向左"和"跳过"按钮设置所选行的操作(手动选择以 `*` 标记),"重置"恢复自动操作,"仅显示已跳过"只显示尚未决定的行。被跳过的差异会保留到下一次同步。
<!--compare-files-->- **Ctrl+Alt+C** – 比较两个面板光标所在的文件，或活动面板中标记的两个文件；对话框显示大小、修改时间和内容比较结果。
  For text files a compare-and-merge window opens: two columns with line numbers and the differences marked in the middle (`~` changed, `<` only on the left, `>` only on the right). **Ctrl+Down** and **Ctrl+Up** move between differences, **Right** copies a difference from left to right, **Left** from right to left, **Ctrl+Z** undoes a copy, **Ctrl+S** writes the changed files with their original encoding and line breaks. Closing with unsaved changes asks for confirmation (a second close discards them). Binary, very large (over 16 MB or 60000 lines) and identical files are shown in the earlier summary window.
<!--compare-folders-->- **Ctrl+Shift+C** – 比较文件夹: 两个面板会选中对方没有的文件,以及同名文件中较新的一个; 时间相同但大小不同则两边都选中。

比较细节:
- 文件夹只在对方没有时才会被选中。
- 比较的是当前面板列表,不含子文件夹,因此在压缩包和 SFTP 中同样可用。
- 对话框会询问以什么作为差异:时间、大小、内容。
- 内容只对磁盘上大小相同的文件逐字节比较,并在后台进行(Esc 取消)。

---

[目录](index.md)
