# SPDX-License-Identifier: GPL-3.0-only
class_name GuideText
extends RefCounted
## 攻略正文 (内容包 guide/*.json 的 body, markdown 子集, docs/内容格式.md §16) -> RichTextLabel 的 BBCode。
## 支持: 标题 # ~ ###### (一律按小标题: 粗体 + 标题色)、列表 - / * (行首每两格空格缩进一级)、粗体 **x**、分隔线 ---、
## 空行 (连续空行算一个; gap_size > 0 时画成该字号的矮行, 段落间不至于空出一整行);
## 其余原样显示 (方括号转义, 内容里的 [ ] 不会被当成 BBCode)。表格等别的语法请在内容里写成列表。

static var _head := RegEx.create_from_string("^(#{1,6})\\s+(.*)$")
static var _bullet := RegEx.create_from_string("^( *)[-*]\\s+(.*)$")
static var _bold := RegEx.create_from_string("\\*\\*(.+?)\\*\\*")


static func to_bbcode(md: String, head_color := Color8(255, 224, 116), gap_size := 0) -> String:
	var hc := head_color.to_html(false)
	# 矮行: 换行符本身也要放在小字号里, 否则这一行仍按正文字号算行高
	var gap := "[font_size=%d] \n[/font_size]" % gap_size if gap_size > 0 else "\n"
	var out := ""
	var pending := false   # 前面有空行, 下一行内容之前补一个间隔 (开头、结尾的空行都不要)
	for raw in md.split("\n"):
		var line := raw.rstrip(" \t\r")
		var t := line.strip_edges()
		if t == "":
			pending = out != ""
			continue
		if pending:
			out += gap
			pending = false
		out += _line(line, t, hc) + "\n"
	return out.trim_suffix("\n")


static func _line(line: String, t: String, hc: String) -> String:
	if t == "---" or t == "***":
		return "[center][color=#%s]· · ·[/color][/center]" % hc
	var m := _head.search(t)
	if m != null:
		return "[b][color=#%s]%s[/color][/b]" % [hc, inline(m.get_string(2))]
	var b := _bullet.search(line)
	if b != null:
		var depth := b.get_string(1).length() / 2
		var item := "[ul bullet=%s]%s[/ul]" % ["·" if depth == 0 else "-", inline(b.get_string(2))]
		return "[indent]".repeat(depth) + item + "[/indent]".repeat(depth)
	return inline(t)


## 行内: 方括号转义, **粗体**
static func inline(s: String) -> String:
	var e := ""
	for ch in s:
		e += "[lb]" if ch == "[" else ("[rb]" if ch == "]" else ch)
	return _bold.sub(e, "[b]$1[/b]", true)
