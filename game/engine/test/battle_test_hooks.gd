# SPDX-License-Identifier: GPL-3.0-only
class_name BattleTestHooks
extends RefCounted
## 战场的测试/调试钩子 (都由命令行开关触发, 正常游玩不走; 参数统一来自 GameContext.debug, 见 engine/core/debug_args.gd):
##   inject        开场注入 (剧情分支验证 仓库外的开发脚本): 改回合/站位/装备/当前体力/阵亡, 再按序执行事件 —— BattleScene 开场调用
##   player_phase  测试回合的开关 (--probe-battle-save / --warp / --wait-at / --hp-unit / --unit / --cast / --idle-player) —— 我方阶段开头调用
## 从 battle_scene.gd / battle_flow.gd 移出 , 战场代码只留一行调用。



## 调试/测试注入 (剧情分支验证, 仓库外的开发脚本): 开场前改好变量/回合/站位/装备, 再直接按序执行若干事件。
##   (--set-var=12:2,16:1 剧情变量在 game.gd 启动时写入; 102:0 = 当前行动者殷剑平)
##   --set-turn=15           当前回合数
##   --place=0:12:22,1:5:5   单位下标:x:y
##   --equip=0:14            单位下标:物品 (按物品类别装到武器/护具/饰物栏)
##   --hp-cur=29:1           单位下标:当前体力 (只改当前; 测试回合改上限+当前的是 --hp-unit=, 见 player_phase)
##   --kill=7,8              单位下标 (当作已阵亡、不再在场)
##   --run-event=5,3,3,2     按序执行事件 (等价于触发源依次触发); 另有 tN/kN/hN/j/TN/n 令牌走正常触发源 (见下); 执行完若战斗没有结束, 记 events_done 检查点
##     tN = 本回合时机 N 的回合事件, kN = 击倒单位 N (掉落/kill_event/胜负判定), hN = 单位 N 离场, iN:物品:x:y = 单位 N 对格使用物品, E = 敌人全部现身, aN:M = N 普攻 M, mN:x:y / sN:x:y = N 走到/停在格 (地图事件), j = 胜负判定, TN = 设回合, n = 回合+1
## 返回 true = 已处理 (不再走正常战斗流程)
static func inject(bs) -> bool:
	var run_list := ""
	for kv0 in bs.gc.debug.inject:   # 按命令行顺序
		var arg: String = kv0[1]
		match String(kv0[0]):
			"set_turn":
				bs.turn = int(arg)
			"place":
				for kv in arg.split(","):
					var p := kv.split(":")
					var u: BattleUnit = bs.unit(int(p[0]))
					if u:
						u.cx = int(p[1])
						u.cy = int(p[2])
			"equip":
				for kv in arg.split(","):
					var p := kv.split(":")
					var u: BattleUnit = bs.unit(int(p[0]))
					if u:
						u.equip_item(int(p[1]))
			"hp_cur":
				for kv in arg.split(","):
					var p := kv.split(":")
					var u: BattleUnit = bs.unit(int(p[0]))
					if u:
						u.st.hp = int(p[1])
			"kill":
				for x in arg.split(","):
					var u: BattleUnit = bs.unit(int(x))
					if u:
						u.alive = false
			"run_event":
				run_list = arg
	if run_list == "":
		return false
	bs.ctl.flow.init_map_events()   # 地图事件表 (mN/sN 令牌用; 正常流程在 BattleFlow.run 开头建)
	for x in run_list.split(","):
		if x.is_valid_int():
			await bs.vm.run(int(x))
		else:  # 经正常流程的触发源: tN 本回合时机 N 的回合事件 / kN 击倒单位 N (掉落、kill_event、胜负判定) / hN 单位 N 离场 / j 胜负判定 / TN 设回合 / n 回合+1
			var flow: BattleFlow = bs.ctl.flow
			var arg := int(x.substr(1)) if x.length() > 1 else 0
			match x[0]:
				"a":  # aN:M = 单位 N 普攻单位 M (写 var100/101, 近景演出, 死亡处理与胜负), 两者须在场且相邻时才有意义
					var pair := x.substr(1).split(":")
					var atk: BattleUnit = bs.unit(int(pair[0]))
					var tgt: BattleUnit = bs.unit(int(pair[1]))
					atk.shown = true
					tgt.shown = true
					await bs.ctl.actions.attack(atk, tgt)
				"m", "s":  # mN:x:y = 单位 N 从 (x,y+1) 走到 (x,y); sN:x:y = 单位 N 停在 (x,y) (没移动); 之后查宝物/地图事件 (Flow.map_event_hit, var102 = 该单位)
					var q := x.substr(1).split(":")
					var mu: BattleUnit = bs.unit(int(q[0]))
					var dst := Vector2i(int(q[1]), int(q[2]))
					mu.shown = true
					if x[0] == "m":
						var from := dst + Vector2i(0, 1)
						mu.cx = from.x
						mu.cy = from.y
						mu.cx = dst.x
						mu.cy = dst.y
						await flow.after_action(mu, [dst], from)
					else:
						mu.cx = dst.x
						mu.cy = dst.y
						await flow.after_action(mu, [], dst)
					if flow.over:
						return true
				"i":  # iN:物品:x:y = 单位 N 对格 (x,y) 使用物品 (走真实 use_item: 发动技能的道具 = 召唤等; 兽魂石 / 剑魂石)
					var iq := x.substr(1).split(":")
					var iu: BattleUnit = bs.unit(int(iq[0]))
					iu.shown = true
					await bs.ctl.actions.use_item(iu, int(iq[1]), Vector2i(int(iq[2]), int(iq[3])))
				"E":  # 所有敌人现身 (正常流程由开场剧情让它们出场; 注入时没跑开场, 否则「敌全灭」条件一开始就成立)
					for eu in bs.units:
						if eu.camp == 1:
							eu.shown = true
				"t":
					await flow._turn_event(arg)
				"k":
					var u: BattleUnit = bs.unit(arg)
					u.st.hp = 0
					u.alive = false
					u.shown = true
					flow.note_killer(u, bs.unit(0))
					await flow.resolve_deaths()
				"h":
					bs.unit(arg).hide_unit()
				"j":
					flow._check_judge()
					if flow.over:
						await bs.vm.run(flow._judge_event)
				"T":
					bs.turn = arg
				"n":
					bs.turn += 1
		if bs.vm.ended:
			return true
	RegressLog.checkpoint("events_done", {"stage": bs.st.n})
	return true



## 测试开关: --cast=技能编号[@x;y],... (第 1 回合我方第一个单位依次对第一个有效落点 / 指定格施放); --idle-player (我方全员原地待機, 对照 AI 走位);
## --warp=unit_id:x,y (第 1 回合把该主角放到格 (x,y), 截宝箱等画面用)
static func player_phase(flow, mine: Array) -> bool:
	for arg in flow.gc.debug.probe_battle_save:  # --probe-battle-save=<回合>:save|check  存读档一致性探针: save 在该回合我方阶段开始时存战阵并记检查点, check (--load-battle 读入后) 记同样的检查点, 两份回归记录对比 (仓库外的开发脚本)
		if flow.bs.turn == int(String(arg).get_slice(":", 0)):
			if String(arg).ends_with(":save"):
				flow.gc.flow.save_battle(flow.bs.snapshot())
			RegressLog.checkpoint("probe", {"turn": flow.bs.turn})
	for arg in flow.gc.debug.warp:
		if flow.bs.turn == flow.test_turn:
			var kv := String(arg).split(":")
			var xy := kv[1].split(",")
			for u in mine:
				if int(u.man["unit_id"]) == int(kv[0]):
					u.set_cell(int(xy[0]), int(xy[1]))
					print("测试: %s 移到 (%s,%s)" % [u.name_text, xy[0], xy[1]])
	for arg in flow.gc.debug.wait_at:
		if flow.bs.turn == flow.test_turn:  # --wait-at=unit_id:x,y 第 1 回合把该主角放到格 (x,y) 并原地待機 (走行动结束的宝物/地图事件检查, 同原版「改坐标再待機」的实测法)
			var kv := String(arg).split(":")
			var xy := kv[1].split(",")
			for u in mine:
				if int(u.man["unit_id"]) == int(kv[0]):
					u.set_cell(int(xy[0]), int(xy[1]))
					print("测试: %s 移到 (%s,%s) 待機" % [u.name_text, xy[0], xy[1]])
					await flow.after_action(u, [], Vector2i(-1, -1))
	for arg in flow.gc.debug.hp_unit:
		if flow.bs.turn == flow.test_turn:  # --hp-unit=unit_id|all:体力 改上限与当前体力 (避免我方战死/可被击杀改变 AI 打分)
			var kv := String(arg).split(":")
			for u in mine:
				if kv[0] == "all" or int(u.man["unit_id"]) == int(kv[0]):
					u.hp_max = int(kv[1])
					u.hp = int(kv[1])
	for arg in flow.gc.debug.unit_edit:
		if flow.bs.turn == flow.test_turn:  # --unit=unit_id:{json} 直接改单位规则状态字段 (对照: 把原版存档里的单位数值照搬过来)
			var at := String(arg).find(":")
			var uid := int(String(arg).substr(0, at))
			var d: Dictionary = JSON.parse_string(String(arg).substr(at + 1))
			for u in flow.bs.units:  # 含敌方/友军 (对照敌方 AI: 改 ai/ai_target/hp 等)
				if (d.has("_idx") and int(d["_idx"]) == u.index) or (not d.has("_idx") and int(u.man["unit_id"]) == uid and u.controllable):
					for k in d:
						if k == "_sr":   # [[位, 剩余值 R, 扣减值 K], ...]
							for e in d[k]:
								u.st.status_r[int(e[0])] = int(e[1])
								u.st.status_k[int(e[0])] = int(e[2])
						elif k == "_shown":
							u.shown = bool(d[k])
						elif d[k] is Array:   # JSON 数字是 float: items.has(220) 对 [220.0] 为假 (道具估价因此被静默跳过), 整数数组一律转 int
							u.st.set(k, d[k].map(func(x): return int(x) if (x is float or x is int) else x))
						elif k != "_idx":
							u.st.set(k, d[k])
	for arg in flow.gc.debug.cast:
		if flow.bs.turn == flow.test_turn:
			for xa in String(arg).split(","):
				var u: BattleUnit = mine[0]
				var at := xa.split("@")  # 技能号@x;y: 强制落点 (演出对照用, 不查射程)
				var x := at[0]
				var sk: Dictionary = flow.rules.skill(int(x))
				u.mp = u.mp_max + int(sk["mp_cost"])
				u.st.moved = false
				u.st.move_left = maxi(u.st.move_left, int(sk["move_cost"]))
				var cells: Array = flow.rules.cast_cells(u, sk)
				if at.size() > 1:
					cells = [Vector2i(int(at[1].split(";")[0]), int(at[1].split(";")[1]))]
				print("测试施放 %s (%s) 落点 %s 帧%d" % [sk["name"], x, cells.slice(0, 3), RegressLog.log_frame])
				if not cells.is_empty() and u.alive:
					await flow.actions.cast(u, sk, cells[0])
				for o in flow.rules.units_alive():
					if o.st.status != 0 or o.summoned:
						print("  %s hp %d/%d mp %d/%d 状态 0x%x%s" % [o.name_text, o.hp, o.hp_max, o.mp, o.mp_max, o.st.status, " 召唤" if o.summoned else ""])
	for arg in flow.gc.debug.cast_as:
		if flow.bs.turn == flow.test_turn:
			var kv := String(arg).split(":")
			var sk: Dictionary = flow.rules.skill(int(kv[1]))
			for u in flow.bs.units:
				if u.controllable or not u.alive or int(u.man["unit_id"]) != int(kv[0]):
					continue
				u.mp = u.mp_max + int(sk["mp_cost"])
				u.st.moved = false
				var t: BattleUnit = mine[0]
				print("测试敌方施放 %s -> %s (%d,%d) 帧%d" % [sk["name"], t.name_text, t.cx, t.cy, RegressLog.log_frame])
				await flow.actions.cast(u, sk, Vector2i(t.cx, t.cy))
				break
	if flow.gc.debug.idle_player:
		print("我方回合 第%d回合 帧%d 全员待機; 在场: %s" % [flow.bs.turn, RegressLog.log_frame, flow.rules.units_alive().map(func(u): return "%s(%d,%d)hp%d%s" % [u.name_text, u.cx, u.cy, u.hp, " 已行动" if u.st.acted else ""])])
		for u in mine:
			flow.rules.end_action(u)
			flow.shade(u)
		return true
	return false

