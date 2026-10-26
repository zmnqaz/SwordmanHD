# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 规则参数集中表。默认值 = 原版 (官方 V1.3, 无补丁)。
## 内容包 / 魔改包用 apply({...}) 覆盖 (键名 = 属性名), to_dict() 导出。
## 实测编号 Txx; 仍未定案的标 TODO(Txx)。
## 覆盖方式与内容包约定见 engine/rules/README.md。规则引擎不读文件: 参数文档由调用方 (内容包加载层 ContentDB) 读好后传入。

# ---------------- 01 属性与成长 ----------------
var stat_cap := 500                 # 五项属性上限
var exp_per_level := 500            # 每 500 经验升 1 级
var level_cap := 99
var hp_grow_const := 3              # HPmax += 3 + (Vit-lv)/35 + rand%(hp_rand+1)
var mp_grow_const := 1              # MPmax += 1 + (Int-lv)/35 + rand%(mp_rand+1)
var grow_attr_div := 35
var spirit_points_per_level := 2    # 高
## 成长随机项: "random" = rand%(N+1) 均匀 0..N (原版 + 连升统计),
## "max" = 恒为 N (龙吟最大成长补丁, 用于对照网上数据), "min" = 恒为 0
var growth_mode := "random"
var hp_cap := 0                     # HPmax 上限: 0 = 不设 (原版无上限)
var mp_cap := 0                     # 同上
## HPmax/MPmax 是 u16, 升级与上限道具直接 16 位加 → 超 65535 回绕。
## 正常流程到不了 (满级约 3500)。false = 封顶 65535
var hp_mp_u16_wrap := true
## 剧情变量号约定 (引擎保留区, 内容包可改; 默认 = 原版)
var var_actor := 102                # 当前行动单位 (玩家选中 / AI 决定行动 / 地图事件触发者写入)
var summon_flag_vars := [103, 104, 105, 106]  # 召唤标志变量: 每关开始清 0, 召唤技使用前检查
## AI 类型别名 {"新类型号": 已有类型号}: 内容包只用数据新增 AI 类型 (行为 = 别名指向的类型)。键为字符串 (JSON), 默认空 = 原版 5 种
var ai_type_alias := {}
## 过关回合数记在变量 base + 下一关号 (原版 30); < 0 = 不记。与通关序号 (0x56) 是同一套原版算法, 见 rules/clear_rank.gd
var turn_record_base := 30
## 通关序号四段 [相对 base 的起点, 个数]: 原版 变量 30~37、38~46、47~54、55~64 求
var clear_rank_segments := [[0, 8], [8, 9], [17, 8], [25, 10]]
## 序号第五项 = 四段之和 xor 此常量
var clear_rank_xor := 0xA50712A5
var skill_slots := 10               # 技能栏 10 格
var spirit_add_limit := 100         # 五魂化蘊: 原值 < 100 才能加 (只比原值, 原版漏洞)

# ---------------- 02 移动 ----------------
var move_avg_div := 25              # MOV = move + Avg/25
var haste_move_num := 3             # 速敏提昇 ×1.5 = ×3/2 后 _ftol 截断 高 (网友数据 45→67)
var haste_move_den := 2
var test_move_bonus := 0              # 仅测试 (--god): 我方移动点额外加成, 让代打在限时关里按时赶到; 缺省 0 = 原版, 不进内容包 rules.json
var bind_move := 1                  # 地縛: 移动点视为 1
## 速敏与保留点: true = int(m×1.5)+R (原版: m=34 → 51, 保留 51 → 上限 102);
## false = int((m+R)×1.5)
var haste_before_reserve := true
var impassable_cost := 0x7FFF       # TER_EFF ×
var zoc_enabled := true             # ZOC: 进入敌对单位上下左右格后停止
## 起点在 ZOC 内时可以离开
var zoc_start_free := true
## 连续爆發: 带保留点未移动时菜单可选, 新保留点 = 当前移动点 字段 (不含旧保留点), 旧保留点丢弃
## 字段 = 字段。true = 累积 (保留点 = 含旧保留点的全部移动点)
var burst_accumulate := false
## 爆發不降防, 只禁止反击 爆發中/未爆發 DEF 同为 27。num/den ≠ 1 时为魔改降防
var burst_def_num := 1
var burst_def_den := 1
## TER_EFF.DAT 单格消耗表。行 = 移动类型 0~11, 列 = 地形类别 0~14
var terrain_cost := [
	[5, 6, 7, 8, 10, 8, 9, 0x7FFF, 0x7FFF, 0x7FFF, 4, 255, 255, 255, 255],
	[6, 7, 8, 9, 10, 9, 9, 0x7FFF, 0x7FFF, 0x7FFF, 4, 255, 255, 255, 255],
	[5, 6, 7, 8, 10, 8, 7, 0x7FFF, 0x7FFF, 0x7FFF, 4, 255, 255, 255, 255],
	[6, 7, 9, 10, 12, 9, 7, 0x7FFF, 0x7FFF, 0x7FFF, 4, 255, 255, 255, 255],
	[6, 6, 6, 6, 8, 8, 6, 12, 0x7FFF, 0x7FFF, 4, 255, 255, 255, 255],
	[7, 7, 7, 7, 7, 7, 7, 7, 7, 0x7FFF, 4, 255, 255, 255, 255],
	[5, 5, 5, 5, 5, 5, 5, 5, 5, 0x7FFF, 4, 255, 255, 255, 255],
	[6, 7, 8, 8, 10, 10, 10, 0x7FFF, 0x7FFF, 0x7FFF, 4, 255, 255, 255, 255],
	[6, 7, 7, 7, 8, 7, 8, 8, 0x7FFF, 0x7FFF, 4, 255, 255, 255, 255],
	[6, 6, 6, 7, 8, 7, 8, 6, 0x7FFF, 0x7FFF, 4, 255, 255, 255, 255],
	[6, 6, 6, 7, 8, 7, 5, 0x7FFF, 0x7FFF, 0x7FFF, 4, 255, 255, 255, 255],
	[0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF, 4, 255, 255, 255, 255],
]

# ---------------- 03 攻击判定 ----------------
var hit_luk_div := 4                # 命中 = 武器hit+饰物hit-(护具miss+饰物miss)+(攻Luk-守Luk)/4
var berserk_crit_num := 3           # 狂暴会心 ×1.5
var berserk_crit_den := 2
var guard_base := 5                 # 格挡率 5 + (守Luk-攻Luk)/10 106 次判定全符
var guard_luk_div := 10
## 格挡方向: true = 守-攻 (原版), false = 攻-守 且基数 6 (龙吟公式, 已否定)
var guard_def_minus_atk := true
var add_luk_div := 10               # 武器附加几率 = add_ratio + (攻Luk-守Luk)/10
var default_attack_range := {"type": 0, "area": 0, "min": 0, "max": 0}   # 无武器: 原版读物品 -1 = 全 0 记录, 菱形 min0/max0 = 只有自身格, 够不到任何人 (无武器守方不反击)
## 「红闪避」演出: 格挡命中时【整个画面】红色闪光, 约 4 帧 (15fps) ≈ 0.3 秒内渐褪;
## 伤害数字【不】变红。只是演出, 规则仍是格挡减伤。guard_flash_sec = 0 关闭闪光
var guard_flash_sec := 0.3
var guard_flash_color := [255, 0, 0]

# ---------------- 04 伤害 ----------------
var atk_up_num := 6                 # 攻擊提昇 ×1.2 (常数)
var atk_up_den := 5
var def_up_num := 6                 # 護禦提昇 ×1.2
var def_up_den := 5
var berserk_atk_mult := 2           # 狂暴 攻×2 防/2
var berserk_def_div := 2
var crit_def_div := 2               # 会心 = 守方防御再减半
var dmg_luk_div_min := 10           # 运气项 Luk/(10+rand%11) (网友数据 一致)
var dmg_luk_div_span := 11
var ai_luk_div := 15                # AI 估算运气项 Luk/15
var min_hit_damage := 1             # 普攻命中保底 1
var double_mult := 2                # 连击 = 伤害 ×2 一次结算
var guard_vit_div := 10             # 普攻格挡 dmg/2 - 守Vit/10 >=1
var min_guard_damage := 1
var tech_up_num := 13               # 技法提昇 power ×1.3
var tech_up_den := 10
var spell_int_rand_div := 20        # P = pw + Int/2 + 1 + rand%(Int/20+1)
var skill_str_div_min := 8          # ot0: + Str/(8+rand%13)
var skill_str_div_span := 13
var skill_ot1_mult := [2, 3, 4]     # ot1 oe0/1/2 倍率
var poison_heal_num := 4            # 中毒时治疗 ×0.8 (常数)
var poison_heal_den := 5
var skill_heal_vit_div := 20            # 技能治疗 ×(100 + Vit/20 + S)/100 [原版 对照: Vit 400 仅 +20%, 旧规格 Vit/10 作废]
var heal_vit_div := 20              # 物品回 HP ×(100 + Vit/20)/100 [原版 调用 对照]
var item_mp_int_div := 20           # 物品回 MP ×(100 + Int/20)/100 [sar 3; 原版 对照 见 HP 项]
var vampire_div := 3                # 吸血 dmg/3 中高
## 武器附加 毒/麻/封: skill=-1 越界读技能表 → R 恒 0。
##   "original": 主攻 R(0) < K → 抵抗, 永不生效; 反击路径照样施加, R=K=0 (目标阵营下一阶段开始即解除)
##   "custom":   主攻/反击都以 R=time、K=cost 施加 (按 R<K 规则)
var weapon_status_mode := "original"
## 武器附加 type 4 = 属性化普攻: dmg × (100-护具抗)(100-饰物抗)/10000 × MAG_OPP[守][武器属性]/100。
## 武器属性 (字段) 无效 (紫金劍 = -1) 时倍率读未初始化栈变量 (未定义行为): 玩家光标普攻 = 目标格 x, AI 估价 = 1, 敌方发起的攻击中
## 紫金劍持有者的反击读到堆指针 (不可复现) → 这里取 0 (伤害取下限 1)。详见 Attack.type4_mult
var weapon_add4_ai_path_mag := 0
var self_destruct_hp_div := 2       # 自爆: 条件 HP <= HPmax/2; 伤害 (HPmax-HP)/2 × MAG_OPP[火]/100

# ---------------- 05 状态 ----------------
var poison_div := 5                 # 中毒每次结算扣 HPmax/5
var poison_lethal := true           # 可致死
var bless_int_div_min := 5          # K = rate10 - 2×(目标Int/(5+rand%6))
var bless_int_div_span := 6
var ai_status_int_div := 7          # AI 估算 2×(Int/7)
var freeze_spirit_mult := 2         # 冰結几率 rate10 - 2×目标魂 80-2×20=40
var freeze_r := 1                   # 冰結 R=1 K=1; 受击即解 (不看伤害是否 >0)
var freeze_k := 1
## 友军 NPC 一轮被结算两次 (友军阶段 + 我方阶段), 原版 bug 照做
var ally_npc_double_tick := true
## rt5 eff16 遁地神行 / eff15 幽冥返召: 原版只扣 MP、播动画, 无效果。
## true = 魔改: 遁地置幻影位 R/K = burrow_r/burrow_k
var burrow_sets_phantom := false
var burrow_r := 0
var burrow_k := 0
## rt5 eff13 返召之咒: 原版只置 字段=1 不重置移动点, 已行动单位移动点已清 0 → 实际不能再行动。
## true = 魔改: 同时把移动点重置为本阶段上限, 可完整再行动一次
var recall_resets_move := false

# ---------------- 07 技能 ----------------
## 魔天降臨 (+0=0 走咒术分支, rt=-1) 原版无效果。true = 魔改修复: 走吸术分支
var fix_mo_tian := false
## 冥幻之陣 rt5 eff7 原版无效果 (扣 500 MP、播动画)。魔改开关, 规则模块暂未定义修复效果
var fix_ming_huan := false
var mp_absorb_div_ot1 := 3          # 攝魂鬼觸 吸术 min(MP, MPmax/3)
var mp_absorb_div_ot2 := 10         # 魔天降臨 吸术 min(MP, MPmax/10)

# ---------------- 08 经验 ----------------
var exp_level_clamp := 10           # d = clamp(目标lv-自身lv, -10, 10)
## 等级曲线常数是 float32 0.1, 运算后向零截断。
## 这正是 "多数项比四舍五入少 1" 的原因 (网友数据 高戚 21 项逐项一致)。
## 向零截断: 两佰士兵 base 7 × k 0.81 = 5.67 实得 5。
var exp_curve_step := 0.100000001490116119384765625
var exp_kill_min := 1               # 击杀经验 <=0 时置 1
var exp_hit_min := 1                # 未击杀经验 >=1
var exp_heal_base := 200            # 治疗经验 200 × k × 回复量 / HPmax, >=1

# ---------------- 09 AI ----------------
var ai_score_threshold := 100       # 主分 < 100 不行动 高 (实测: 单目标 HP<=40% 才吃药/被治疗, 第3路)
var ai_attack_base := 100           # 普攻/伤害技能 100, 可击杀 +50
var ai_kill_bonus := 50
var ai_heal_tiers := [[40, 100], [60, 50], [80, 10]]   # HP% <=40 +100, 40~60 +50, 60~80 +10
var ai_status_each := 50            # 增益/诅咒 每人 +50, 上限 150
var ai_status_cap := 150
var ai_buff_enemy_radius := 12      # 攻/防/速/狂暴 类要求目标 12 格内有敌人
var ai_status_dmg_base := 110       # 带状态/吸术/驱散的绝技 (ot1 oe3~6、ot2 oe12) 主分 110, 末条目击杀 +30 [字段/字段]
var ai_status_dmg_kill := 30
var ai_recall_each := 40            # 返召之咒 (结果码 0x14): 范围内每个【本阶段已行动】(字段==0) 的友军 +40, 不封顶
var ai_recall_count_idle := true    # 「轮到过但没动」的 AI 单位 (待命/被动无目标) 也算已行动
var ai_phantom_score := 110         # 幻影 (无方变幻, 祝福 eff7) 固定 110 [字段; 原规格误记为「遁地」]
var ai_mp_restore_score := 130      # [字段] 仅 ot2 oe7 吸术分支 (魔天降临, 咒术走不到) 用; 实际数据中无技能到达, 保留常量
var ai_cure_each := 50              # 解毒/麻/封道具 每人 50
var ai_use_items := true            # 道具参与统一打分 敌人对自己/相邻友军用药, 从使用者物品栏扣
var ai_crowd_radius := 4            # 走向敌群: 敌人 4 格菱形内累加权重 中高
## 权重随距离: 下标 = 距离 0..4。 累加 (范围洪泛, 参数 max=4 min=0) 输出每格的 +8 字段 =
## 洪泛标记值: 起点 4, 距离 1 为 4, 距离 2 为 3, 距离 3 为 2, 距离 4 为 1 (标记写成「父格当前值」, 子格入队值再减 1)
var ai_crowd_weights := [4, 4, 3, 2, 1]

# ---------------- 10 回合流程与胜负 ----------------
var turn_limit := 100               # turn >= 100 → GAME OVER (消息 0x516)
## 中毒等状态致死后, 仅当死者 kill_event ≠ -1 才判胜负; 否则等下一次行动结算
var status_death_judge_needs_event := true
## 结局过场 (内容包 ending_movies, 原版 Movie_13) 播完、脚本 END 且没有出口指令时:
## 原版停在黑屏, 战斗在后台空转, 玩家无法操作 —— 脚本缺陷。
## true = 复刻修补: 回到标题 (默认开); false = 原版黑屏
var fix_ending_return_title := true

# ---------------- 11 物品与金钱 ----------------
var unit_item_slots := 10           # 每人随身 10 格 (装备占格)
var bag_capacity := 512             # 公共行囊 512 格
var initial_gold := 5               # 新游戏 5 两, 第 0 幕不改
var equip_costs_action := false     # 战斗中装备/丢弃不消耗行动与移动点
var battle_save_after_action := false  # 战阵存档: 我方已有人行动后存档项变灰; true = 随时可存 (魔改)
var give_costs_action := true       # 战斗中「交給」消耗行动


func _init(overrides: Dictionary = {}) -> void:
	apply(overrides)


## 覆盖参数 (内容包 / 改动包)。未知键报错并忽略; JSON 数字 (float) 按原属性类型转换。
## 校验 (内容包写错不该在战斗里才除零/静默失效): 类型与缺省值不符、除数 (*_div*, *_span) 小于 1 时报错并保留原值。
func apply(overrides: Dictionary) -> void:
	for k in overrides:
		if not (k in self):
			push_error("RulesParams: 未知参数 %s" % k)
			continue
		var cur = get(k)
		var v = overrides[k]
		if cur is int and v is float:
			v = int(v)
		elif cur is float and v is int:
			v = float(v)
		elif cur is Array and v is Array:
			v = _int_array(v)
		if typeof(v) != typeof(cur):
			push_error("RulesParams: 参数 %s = %s 类型不对 (应为 %s), 保留 %s" % [k, str(overrides[k]), type_string(typeof(cur)), str(cur)])
			continue
		if v is int and _is_divisor(String(k)) and v < 1:
			push_error("RulesParams: 参数 %s = %d 是除数, 须 >= 1, 保留 %s" % [k, v, str(cur)])
			continue
		set(k, v)


## 用作除数 / rand()% 模数的参数 (*_div, *_div_min, *_div_ot1, *_span …)
static func _is_divisor(k: String) -> bool:
	return "_div" in k or k.ends_with("_span")


## 应用一份参数文档 (已解析的 JSON): {"format": "tdj-rules/1", "params": {...}} 或直接 {参数: 值}
func apply_document(d: Dictionary) -> void:
	apply(d.get("params", {}) if d.has("params") else d)


## 按顺序 (基础包 → 改动包…) 依次叠加各份参数文档; 原版内容包没有文档: 默认值就是原版。
static func from_documents(docs: Array):
	var p = load("res://engine/rules/params.gd").new()
	for d in docs:
		if d is Dictionary:
			p.apply_document(d)
	return p


static func _int_array(a: Array) -> Array:
	var out := []
	for x in a:
		if x is float and x == floor(x):
			out.append(int(x))
		elif x is Array:
			out.append(_int_array(x))
		else:
			out.append(x)
	return out


func to_dict() -> Dictionary:
	var d := {}
	for p in get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			d[p.name] = get(p.name)
	return d


func terrain_move_cost(move_type: int, terrain_class: int) -> int:
	if move_type < 0 or move_type >= terrain_cost.size():
		return impassable_cost
	var row: Array = terrain_cost[move_type]
	if terrain_class < 0 or terrain_class >= row.size():
		return impassable_cost
	return row[terrain_class]
