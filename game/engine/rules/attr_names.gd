# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 魂名 / 属性键 / 抗性名的单一来源 (X3#4 收口): 存档、营地、战场详情、成长、属性计算都读这里, 不再各写一份。
## 个数 (5 魂 / 5 属性 / 6 抗) 是原版数据形状 (引擎固定), 名字与顺序是约定; 改名要同步存档键。
## 值与原版一致, 行为不变。

## 五魂 (迅烈神魔魂) 存档/营地格式的键, 下标 = 单位 字段.. 的魂序号
const SPIRIT := ["迅", "烈", "神", "魔", "魂"]
## 五项属性键, 下标 = 单位 字段.. 的存储顺序 (str int avg vit luk)
const STAT_KEYS := ["str", "int", "avg", "vit", "luk"]
## 营地人物页点表的显示顺序 攻 防 咒 行 運, 同一组键, 仅顺序不同
const STAT_DISPLAY := ["str", "vit", "int", "avg", "luk"]
## 六系抗性键, 显示顺序 火 雷 冰 幻 光 暗; 与护具/饰物 attribute_defence 表同键
const RES_KEYS := ["火", "雷", "冰", "幻", "光", "暗"]
