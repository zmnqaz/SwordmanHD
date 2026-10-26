# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 命令行调试参数的唯一解析处 DebugArgs (engine/core/debug_args.gd): 引擎只读字段


func test_seed():
	eq(DebugArgs.parse(["--seed=42"]).rng_seed, 42, "整数种子")
	eq(DebugArgs.parse(["--seed=-7"]).rng_seed, -7, "负数也是整数")
	eq(DebugArgs.parse([]).rng_seed, null, "没传: null (随机种子)")
	eq(DebugArgs.parse(["--seed=abc"]).rng_seed, null, "非数字: 报错, 按没传处理 (以前静默变 0)")
	eq(DebugArgs.parse(["--seed=abc", "--seed=9"]).rng_seed, 9, "跳过坏的取下一个")
	eq(DebugArgs.parse(["--seed=3", "--seed=9"]).rng_seed, 3, "第一个有效的为准")


func test_switches():
	var d := DebugArgs.parse(["--fast", "--autoplay", "--god", "--ai-trace"])
	check(d.fast and d.god and d.ai_trace, "开关")
	check(d.autoplay, "--autoplay 是代打")
	check(d.test_run and not DebugArgs.parse(["--lang=hant"]).test_run, "自动测试运行 (不录像) 的判定")


## --hp 拆成两个含义明确的参数: --hp-cur (开场注入, 单位下标, 只改当前体力) / --hp-unit (测试回合, unit_id 或 all, 改上限+当前)
func test_hp_split():
	var d := DebugArgs.parse(["--hp-cur=29:1", "--hp-unit=all:600", "--place=0:20:20"])
	eq(d.inject, [["hp_cur", "29:1"], ["place", "0:20:20"]], "开场注入按命令行顺序")
	eq(d.hp_unit, ["all:600"])
	var old := DebugArgs.parse(["--hp=29:1"])
	check(old.inject.is_empty() and old.hp_unit.is_empty(), "旧的 --hp= 不再生效 (报错提示改用哪个)")


func test_ordered_lists():
	var d := DebugArgs.parse(["--give=210", "--gold=5", "--set-var=12:1", "--run-event=t0,k3", "--walk=3,4", "--auto-exit"])
	eq(d.state_edits, [["give", "210"], ["gold", "5"], ["set_var", "12:1"]], "改进度按顺序")
	eq(d.run_event, "t0,k3")
	eq(d.town_walk, [["run_event", "t0,k3"], ["walk", "3,4"], ["auto_exit", ""]], "城镇测试动作按顺序")
	eq(DebugArgs.parse(["--choose=1,0"]).choose, [true, false])
	eq(DebugArgs.parse(["--scene=stage3", "--scene=title"]).scene, "stage3", "--scene 取第一个")


func test_settings_override_and_assets():
	var d := DebugArgs.parse(["--gfx=orig", "--lang=hant", "--coord=1", "--tex-mult=2", "--aspect=16:10"])
	eq(d.cli_overrides, {"gfx": "orig", "lang": "hant", "coord": 1})
	check(d.gfx_orig, "--gfx=orig 也给贴图层")
	eq(d.tex_mult, 2)
	near(d.aspect, 1.6, 0.0001)
	eq(DebugArgs.parse([]).tex_mult, -1, "没给 = -1 (贴图层保留缺省)")
	eq(DebugArgs.parse([]).mods, null, "没给 --mods: 用设定文件里的")
	eq(DebugArgs.parse(["--mods=a,b"]).mods, ["a", "b"])


## 测试钩子脚本 (只在带命令行开关时才跑到) 至少要能编译
func test_test_hooks_compile():
	for p in ["res://engine/test/battle_test_hooks.gd"]:
		var s: GDScript = load(p)
		check(s != null and s.can_instantiate(), "%s 能编译" % p)


func test_replay_switch_arg():
	eq(DebugArgs.parse(["--replay-switch=/tmp/a.json"]).replay_switch, "/tmp/a.json")
	eq(DebugArgs.parse([]).replay_switch, "", "缺省空")
