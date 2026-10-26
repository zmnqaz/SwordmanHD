# SPDX-License-Identifier: GPL-3.0-only
extends SceneTree
## 极简测试运行器 (无插件)。用法:
##   tools/godot/godot --headless --path game --script res://tests/run_tests.gd [-- 过滤串] [--group=fast|slow|all] [--slowest=N] [--list]
## 扫描 res://tests/ 下 test_*.gd, 逐个执行其中 test_ 开头的方法。退出码 0 = 全部通过, 1 = 有失败。
## 测试文件可在顶部声明 (都是可选常量):
##   const GROUP := "slow"                       分组: 缺省 fast; slow = 单文件耗时长 (forge 等), --group=fast 时不跑, CI full/nightly 跑全部
##   const REQUIRES := ["original"]              整个文件依赖的外部产物: original (原版资源) / hd4x / content (game/content/tdj) / data (data/*.json)
##   const REQUIRES_TEST := {"test_x": ["original"]}  只有个别方法依赖时按方法声明
## 缺依赖时该测试记 SKIP (不是失败, 也不是误报通过); 环境变量 CI_REQUIRE_ORIGINAL=1 时缺依赖算失败。
## 测试内部发现缺东西 (动态判断) 可调 skip("原因") 后 return。
## 退出时打印最慢的 N 个测试 (--slowest=N, 缺省 8)。
## 每个测试至少要有一次断言, 否则 (多半是中途脚本出错) 记为失败。
## 在第一帧开始跑 (_initialize 时根节点还不在树里, 节点的全局变换等用不了; 指针命中测试要用)。

## 捕获脚本错误 (运行时 SCRIPT ERROR): 测试里任何脚本报错都算失败, 不能因为断言碰巧通过就放过
class ScriptErrorLogger extends Logger:
	var errors: Array = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array) -> void:
		if error_type == Logger.ERROR_TYPE_SCRIPT:
			errors.append("%s:%d %s %s" % [file.get_file(), line, code, rationale])


const TestBase = preload("res://tests/test_base.gd")

var _logger := ScriptErrorLogger.new()


func _initialize() -> void:
	OS.add_logger(_logger)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var filter := ""
	var group := "all"
	var slowest := 8
	var list_only := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--group="):
			group = a.trim_prefix("--group=")
		elif a.begins_with("--slowest="):
			slowest = int(a.trim_prefix("--slowest="))
		elif a == "--list":
			list_only = true
		elif not a.begins_with("--"):
			filter = a
	var require_all := OS.get_environment("CI_REQUIRE_ORIGINAL") == "1"
	var timings := []  # [毫秒, 名字]
	var skipped := 0
	var skip_by_need := {}
	var orphan_tests := []
	var files := []
	var dir := DirAccess.open("res://tests")
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	var total := 0
	var failed := 0
	var failures := []
	var t0 := Time.get_ticks_msec()
	for f in files:
		var script = load("res://tests/" + f)
		if script == null or not script.can_instantiate():  # 解析错误的测试文件也算失败, 不能悄悄少跑
			failed += 1
			failures.append("%s: 无法加载" % f)
			continue
		var consts: Dictionary = script.get_script_constant_map()
		var file_group := String(consts.get("GROUP", "fast"))
		if group != "all" and file_group != group:
			continue
		var file_needs: Array = consts.get("REQUIRES", [])
		var test_needs: Dictionary = consts.get("REQUIRES_TEST", {})
		var names := []
		for m in script.get_script_method_list():
			if str(m.name).begins_with("test_") and not names.has(m.name):
				names.append(m.name)
		for n in names:
			if filter != "" and not (f + ":" + n).contains(filter):
				continue
			if list_only:
				print("%s:%s [%s]" % [f, n, file_group])
				continue
			var missing := []
			for need in file_needs + test_needs.get(n, []):
				if not TestBase.has_resource(need) and not missing.has(need):
					missing.append(need)
			if not missing.is_empty():
				if require_all:
					total += 1
					failed += 1
					failures.append("%s:%s\n      缺依赖 %s 且 CI_REQUIRE_ORIGINAL=1" % [f, n, ",".join(missing)])
					print("  FAIL %s:%s (缺 %s)" % [f, n, ",".join(missing)])
				else:
					skipped += 1
					for need in missing:
						skip_by_need[need] = skip_by_need.get(need, 0) + 1
					print("  skip %s:%s (缺 %s)" % [f, n, ",".join(missing)])
				continue
			var inst = script.new()
			inst.current_test = n
			_logger.errors.clear()
			var t_test := Time.get_ticks_msec()
			var orphans0 := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
			await inst.call(n)  # 协程 (含 await 的测试) 会等到跑完; 同步测试立即返回
			timings.append([Time.get_ticks_msec() - t_test, "%s:%s" % [f, n]])
			var leaked := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) - orphans0
			if leaked > 0:  # 测试里 new() 出来的节点没 free: 退出时 ObjectDB 泄漏警告的来源 (诊断用, 不算失败)
				orphan_tests.append("%s:%s (+%d)" % [f, n, leaked])
			if inst.skipped_reason != "" and inst.failures.is_empty() and _logger.errors.is_empty():
				if require_all:
					failed += 1
					total += 1
					failures.append("%s:%s\n      动态跳过 (%s) 且 CI_REQUIRE_ORIGINAL=1" % [f, n, inst.skipped_reason])
					print("  FAIL %s:%s (跳过: %s)" % [f, n, inst.skipped_reason])
				else:
					skipped += 1
					skip_by_need["动态"] = skip_by_need.get("动态", 0) + 1
					print("  skip %s:%s (%s)" % [f, n, inst.skipped_reason])
				continue
			total += 1
			for e in _logger.errors:
				inst.failures.append("脚本错误: " + e)
			if inst.failures.size() > 0 or inst.assert_count == 0:
				failed += 1
				var msgs: Array = inst.failures.duplicate()
				if inst.assert_count == 0:
					msgs.append("没有执行任何断言 (测试中途出错?)")
				failures.append("%s:%s\n      %s" % [f, n, "\n      ".join(msgs)])
				print("  FAIL %s:%s" % [f, n])
			else:
				print("  ok   %s:%s (%d)" % [f, n, inst.assert_count])
	print("")
	if list_only:
		quit(0)
		return
	timings.sort_custom(func(a, b): return a[0] > b[0])
	if slowest > 0:
		print("最慢的 %d 个测试:" % mini(slowest, timings.size()))
		for i in mini(slowest, timings.size()):
			print("  %6d ms  %s" % [timings[i][0], timings[i][1]])
	for fl in failures:
		print("FAIL " + fl)
	if not orphan_tests.is_empty():
		print("\n遗留孤儿节点的测试 (没 free, 退出时会报 ObjectDB 泄漏; 不算失败): " + ", ".join(orphan_tests))
	if skipped > 0:
		print("\n跳过 %d 个 (缺依赖 %s)" % [skipped, skip_by_need])
	print("\n%d 个测试, %d 失败, %d 跳过, 用时 %d ms" % [total, failed, skipped, Time.get_ticks_msec() - t0])
	quit(1 if failed > 0 or total == 0 else 0)
