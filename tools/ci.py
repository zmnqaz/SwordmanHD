#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""本地与 CI 共用的唯一检查入口 (跨平台实现; tools/ci.sh 是调用本文件的薄封装)。
  python tools/ci.py fast      (提交前) Godot --import + 无头测试 (--group=fast) + content_schema + check_ui_text + layout_stats + 文档检查
                               + tools/tests/ Python 测试 + 换行/绝对路径/SPDX 头守卫
  python tools/ci.py full      fast + 慢测试组 (单文件耗时长的测试)
  单项: python tools/ci.py <档位> --only <步骤名>[,<步骤名>] ; --list 列出本档位的步骤
环境变量:
  CI_LOG_DIR           日志与中间产物目录 (默认 <仓库>/.work/ci); 每步一个 <步骤>.log, 汇总在 summary.txt
  CI_GODOT / TDJ_GODOT Godot 可执行文件 (默认 tools/godot/godot[.exe], 要求 4.7.2; 另可写 tools/dev_env.json)
退出码: 0 全部通过 (允许有 SKIP), 1 有失败, 2 用法或环境错误 (缺 Godot 等)。
测试隔离: 用户数据目录 (Linux XDG_*, Windows APPDATA/LOCALAPPDATA) 指向 $CI_LOG_DIR/home 下的空目录, 不读本机真实设置与存档。
Windows 上 Godot 请用 *_console.exe (GUI 版不把输出写到管道)。
"""
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import paths  # noqa: E402

ROOT = paths.REPO
USAGE = __doc__.split("环境变量:")[0].strip("\n")


def fwd(p):
    return p.replace("\\", "/")


class Ci:
    def __init__(self, mode):
        self.mode = mode
        self.godot = paths.godot_exe()
        log = os.environ.get("CI_LOG_DIR") or os.path.join(ROOT, ".work", "ci")
        self.log = os.path.abspath(log)
        self.results = []  # (名字, 状态, 秒, 备注)
        self.only = None   # --only 指定的步骤名集合
        self.listing = False
        self.env = None
        self.ver = ""

    # ---- 准备 ----
    def prepare(self):
        if not os.path.isfile(self.godot):
            print(paths.missing_godot_hint())
            return 2
        try:
            self.ver = subprocess.run([self.godot, "--version"], capture_output=True, text=True, timeout=60).stdout.strip().splitlines()[0]
        except Exception:
            self.ver = ""
        if not self.ver.startswith(paths.EXPECT_GODOT + "."):
            print("警告: Godot 版本 '%s' 不是 %s, 结果可能与基线不一致" % (self.ver, paths.EXPECT_GODOT), file=sys.stderr)
        for sub in ("home",):
            shutil.rmtree(os.path.join(self.log, sub), ignore_errors=True)
        if os.path.isdir(self.log):
            for f in os.listdir(self.log):
                if f.endswith(".log") or f == "summary.txt":
                    os.remove(os.path.join(self.log, f))
        for sub in ("home/data", "home/config", "home/cache"):
            os.makedirs(os.path.join(self.log, sub), exist_ok=True)
        env = paths.env_for_godot()
        home = os.path.join(self.log, "home")
        env.update(XDG_DATA_HOME=os.path.join(home, "data"), XDG_CONFIG_HOME=os.path.join(home, "config"), XDG_CACHE_HOME=os.path.join(home, "cache"))
        if os.name == "nt":  # Godot 的 user:// 在 Windows 是 %APPDATA%\Godot
            env.update(APPDATA=os.path.join(home, "data"), LOCALAPPDATA=os.path.join(home, "cache"))
        env["PYTHONIOENCODING"] = "utf-8"
        self.env = env
        return 0

    # ---- 记录 ----
    def record(self, name, state, secs, note=""):
        self.results.append((name, state, secs, note))
        print("[%s] %s (%d 秒)%s" % (state, name, secs, " - " + note if note else ""), flush=True)

    def run(self, cmd, logname, timeout=None):
        """跑命令, 输出进日志; 返回退出码 (超时 124)。"""
        with open(os.path.join(self.log, logname + ".log"), "wb") as f:
            try:
                return subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, env=self.env, cwd=ROOT, timeout=timeout).returncode
            except subprocess.TimeoutExpired:
                f.write(("超时 (%s 秒) 被终止\n" % timeout).encode("utf-8"))
                return 124
            except OSError as e:
                f.write(("无法启动 %s: %s\n" % (cmd[0], e)).encode("utf-8"))
                return 127

    def want(self, name):
        return self.only is None or name in self.only

    def step(self, name, cmd, warn_only=False):
        """warn_only: 失败只记 WARN (新守卫先观察一段时间再转成硬失败)"""
        if not self.want(name):
            return
        t0 = time.time()
        print("==> " + name, flush=True)
        rc = self.run(cmd, name)
        dt = int(time.time() - t0)
        if rc == 0:
            # 工具自己判断缺产物时输出 "SKIP: ..." (tools/paths.py require()), 不能记成通过
            try:
                m = re.search(r"^(SKIP.*)$", open(os.path.join(self.log, name + ".log"), encoding="utf-8", errors="replace").read(), re.M)
            except OSError:
                m = None
            if m:
                self.record(name, "SKIP", dt, m.group(1)[:200])
            else:
                self.record(name, "PASS", dt)
        else:
            self.record(name, "WARN" if warn_only else "FAIL", dt, "退出码 %d, 日志 %s" % (rc, os.path.join(self.log, name + ".log")))

    def skip(self, name, why):
        if self.want(name):
            self.record(name, "SKIP", 0, why)

    # ---- 具体步骤 ----
    def godot_cmd(self, *args):
        return [self.godot, "--headless", "--path", fwd(os.path.join(ROOT, "game"))] + list(args)

    def godot_tests(self, name, group):
        """无头单元测试。依赖声明与 SKIP 由 run_tests.gd 负责 (头注), 这里只汇总; CI_REQUIRE_ORIGINAL=1 时缺依赖由它判失败。"""
        if not self.want(name):
            return
        t0 = time.time()
        print("==> " + name, flush=True)
        logp = os.path.join(self.log, name + ".log")
        rc = self.run(self.godot_cmd("--script", "res://tests/run_tests.gd", "--", "--group=" + group), name)
        text = open(logp, encoding="utf-8", errors="replace").read()
        m = re.findall(r"^.*个测试, \d+ 失败.*$", text, re.M)
        summary = m[-1] if m else ""
        slow = re.search(r"最慢的 \d+ 个测试:\n((?:  .*\n){1,3})", text)
        if slow:
            summary += " | 最慢: " + "; ".join(l.strip() for l in slow.group(1).splitlines())
        sk = re.search(r"^跳过 (\d+) 个 \(缺依赖 (.*)\)$", text, re.M)
        if sk:
            summary += " | 跳过 %s 个缺依赖 %s" % (sk.group(1), re.sub(r"\s+", " ", sk.group(2)))
        dt = int(time.time() - t0)
        if rc == 0:
            return self.record(name, "PASS", dt, summary)
        if re.search(r"\b0 个测试, 0 失败", text):   # 这一组没有可跑的测试 (全都缺依赖 / 没有这一组): 整组跳过, 不算失败
            return self.record(name, "SKIP", dt, summary)
        self.record(name, "FAIL", dt, "退出码 %d, 日志 %s; %s" % (rc, logp, summary))

    def tool(self, *a):
        return [sys.executable, os.path.join(HERE, *a)]

    def main(self):
        t_all = time.time()
        if not self.listing:
            print("ci.py %s | Godot %s | 日志 %s" % (self.mode, self.ver, self.log), flush=True)
        tests = os.path.join(HERE, "tests")
        # ---- fast: 每次提交 ----
        self.step("git-eol", self.tool("checks", "check_eol.py"))  # 行尾 (.gitattributes 是否被 core.autocrlf 搞坏)
        self.step("no-abs-paths", self.tool("checks", "no_abs_paths.py"))  # 写死本机路径 (本机目录 / worktree 名), 硬失败
        self.step("spdx", self.tool("legal/spdx_headers.py") + ["--check"])  # 代码文件第一行 (shebang 之后) 的 SPDX 许可头 (GPL-3.0-only; 第三方着色器见脚本 OVERRIDES)
        self.step("godot-import", self.godot_cmd("--import"))
        self.godot_tests("godot-tests", "fast")
        self.step("content-schema", self.tool("checks", "content_schema.py") + ["--strict"])
        self.step("ui-text", self.tool("checks", "check_ui_text.py"))   # 代码里不再新增写死的中文 (玩家可见的走 UiStrings, 繁体才跟得上)
        self.step("layout-stats", self.tool("checks", "layout_stats.py") + ["--check"])
        self.step("docs-check", self.tool("checks/check_docs.py") + ["--all", "--strict"])  # 文档断链 / 未被 README 索引
        self.step("python-tests", [sys.executable, "-m", "unittest", "discover", "-v", "-s", tests, "-t", tests])
        # ---- full: 合并前 ----
        if self.mode == "full":
            self.godot_tests("godot-tests-slow", "slow")  # 单文件 >4 秒的测试
        return 0 if self.listing else self.summary(time.time() - t_all)

    def list_steps(self):
        """--list: 不执行, 只列出本档位会跑的步骤 (用 main() 的同一份编排, 把执行换成登记)"""
        names = []
        for meth in ("step", "godot_tests"):
            setattr(self, meth, (lambda *a, **k: names.append(a[0])))
        self.skip = lambda name, why: names.append(name)
        self.main()
        print("\n".join(names))
        return 0

    def summary(self, total):
        nfail = sum(1 for r in self.results if r[1] == "FAIL")
        nskip = sum(1 for r in self.results if r[1] == "SKIP")
        nwarn = sum(1 for r in self.results if r[1] == "WARN")
        lines = ["ci %s 汇总 (总用时 %d 秒)" % (self.mode, total)]
        for name, state, secs, note in self.results:
            lines.append("  %-5s %-18s %5d 秒  %s" % (state, name, secs, note))
        lines.append("结果: %s, 跳过 %d 项%s" % ("通过" if nfail == 0 else "失败 %d 项" % nfail, nskip, ", 警告 %d 项 (不影响通过)" % nwarn if nwarn else ""))
        text = "\n".join(lines)
        print(text)
        with open(os.path.join(self.log, "summary.txt"), "w", encoding="utf-8") as f:
            f.write(text + "\n")
        if nfail:
            for name, state, _, _ in self.results:
                lp = os.path.join(self.log, name + ".log")
                if state == "FAIL" and os.path.isfile(lp) and os.path.getsize(lp):
                    print("\n---- 失败步骤 %s 日志末尾 (全文 %s) ----" % (name, lp))
                    body = open(lp, encoding="utf-8", errors="replace").read().splitlines()
                    if name.startswith("godot-tests") and any(l.startswith("FAIL ") for l in body):
                        out, i = [], 0
                        while i < len(body):
                            if re.match(r"FAIL |非预期失败", body[i]):
                                out += body[i:i + 5]
                                i += 5
                            else:
                                i += 1
                        print("\n".join(out[:60]))
                    else:
                        print("\n".join(body[-30:]))
            return 1
        return 0


def main(argv):
    mode = argv[0] if argv else ""
    rest = argv[1:]
    if mode in ("-h", "--help"):
        print(USAGE)
        return 0
    if mode == "":
        print(USAGE)
        return 2
    if mode not in ("fast", "full"):
        print("未知子命令 %s (fast|full)" % mode)
        return 2
    ci = Ci(mode)
    while rest:
        a = rest.pop(0)
        if a == "--only" and rest:
            ci.only = set(rest.pop(0).split(","))
        elif a == "--list":
            ci.listing = True
        else:
            print("未知参数 %s" % a)
            return 2
    if ci.listing:
        return ci.list_steps()
    rc = ci.prepare()
    return rc or ci.main()


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8")  # Windows 控制台默认 GBK, 日志含中文
    except Exception:
        pass
    sys.exit(main(sys.argv[1:]))
