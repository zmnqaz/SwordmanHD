# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 商店物品窗: 左栏标签按店种 (原版名称), 买不起的货整行压暗,
## 进店右栏初值 = 第一个在队主角 (栏序 [商店] 行囊 各主角)。
const REQUIRES := ["content"]  # 缺则整个文件 SKIP (run_tests.gd 头注); 实测: 移走对应产物后这些测试失败
const REQUIRES_TEST := {
	"test_shop_poor_rows_dim_and_side_col": ["original"],
	"test_shop_target_full_dims_and_no_prompt": ["original"]
}  # 个别方法的依赖 (同上)

var _saved: Dictionary


func _assets_ready() -> bool:
	var A = _tree().root.get_node_or_null("Assets")
	var C = _tree().root.get_node_or_null("Content")
	if A == null or C == null:
		return false
	if A._index.is_empty():
		A._ready()
	if C.packs.is_empty():
		C.load_packs([ContentDB.default_main()])
	return true


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _setup() -> void:
	_saved = {"bag": Game.state.bag.duplicate(), "party": Game.state.party.duplicate(true), "gold": Game.state.gold}
	Game.state.party = {0: {"lv": 1, "items": [], "gear": {}, "skills": [], "spirit": {}, "stats": {}}}


func _teardown() -> void:
	Game.state.bag = _saved["bag"]
	Game.state.party = _saved["party"]
	Game.state.gold = _saved["gold"]


func test_shop_column_names():
	if not _assets_ready():
		check(true)
		return
	eq(CampInventory.new([0], 0).col(0)["name"], "武器店", "店种 0 = 武器店")
	eq(CampInventory.new([0], 1).col(0)["name"], "杂物店", "店种 1 = 杂物店")
	eq(CampInventory.new([0], 2).col(0)["name"], "药店", "店种 2 = 药店")
	eq(CampInventory.new([0], 9).col(0)["name"], "商店", "未知店种回退商店")
	eq(CampInventory.new().col(0)["name"], "行囊", "非商店模式不变")
	# 店种名是内容包数据 (enums.shop_type), 代码里不留名称表
	eq(CampInventory.new([0], 1).col(0)["name"], String(Content.enums("shop_type").get("1")), "标签取 enums.shop_type")
	check(not CampInventory.new().get_script().get_script_constant_map().has("SHOP_TYPE_NAMES"), "没有代码常量名称表")


func test_shop_poor_rows_dim_and_side_col():
	if not _assets_ready():
		check(true)
		return
	_setup()
	var price := int(CampInventory.item(0)["price"])
	check(price > 0, "测试用物品有价格")
	# 右栏初值 = 第一个在队主角 (栏序 商店0 行囊1 主角2)
	var w := CampItemWindow.new(CampInventory.new([0, 1], 2))
	_tree().root.add_child(w)
	w.open()
	eq(w.side_col, [0, 2], "商店模式右栏初值为第一个主角")
	# 买不起整行压暗
	Game.state.gold = price - 1
	w._rebuild(0)
	var rows := w._panels[0].get_children().filter(func(c): return c is Node2D and c.position.x == 5)
	check(rows.size() >= 2, "商店栏画出了货品行")
	near(rows[0].modulate.a, CampItemWindow.SHOP_POOR_ALPHA, 0.001, "买不起: 压暗")
	# 买得起恢复正常
	Game.state.gold = price * 2 + 100
	w._rebuild(0)
	rows = w._panels[0].get_children().filter(func(c): return c is Node2D and c.position.x == 5)
	near(rows[0].modulate.a, 1.0, 0.001, "买得起: 不压暗")
	w.free()
	_teardown()


## 原版实测 /:
## 对面栏 (买入去处) 满了 = 货品整行压暗 (即使钱够), 确认不弹问句; 商店栏上按 ←/→ 左栏换成行囊 (商店在栏环里)
func test_shop_target_full_dims_and_no_prompt():
	if not _assets_ready():
		check(true)
		return
	_setup()
	Game.state.gold = 1000
	Game.state.party[0]["items"] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
	var w := CampItemWindow.new(CampInventory.new([0, 1], 2))
	_tree().root.add_child(w)
	w.open()
	var rows := w._panels[0].get_children().filter(func(c): return c is Node2D and c.position.x == 5)
	near(rows[0].modulate.a, CampItemWindow.SHOP_POOR_ALPHA, 0.001, "钱够但主角栏满 10 格: 压暗")
	w.key("accept")
	check(w._ask == null, "买不了: 确认不弹问句")
	w.key("left")
	eq(w.side_col[0], 1, "商店栏上按 ← 左栏换成行囊 (原版)")
	w.key("right")
	eq(w.side_col[0], 0, "再按回到商店 (只有一个主角时环里只有 商店/行囊)")
	# 对面栏换成行囊 (有空位): 恢复, 确认弹「是否要买入」
	w.key("tab")
	w.key("right")
	eq(w.side_col[1], 1, "右栏换成行囊")
	w.key("tab")
	rows = w._panels[0].get_children().filter(func(c): return c is Node2D and c.position.x == 5)
	near(rows[0].modulate.a, 1.0, 0.001, "目标栏有空位且钱够: 不压暗")
	w.key("accept")
	check(w._ask != null, "买得起: 弹问句")
	w.free()
	_teardown()
