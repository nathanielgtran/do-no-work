#!/usr/bin/env python3
"""push-guard: shared command normaliser for autonomy-gate.sh and openspec-autonomy.sh.

stdin: hook JSON ({tool_input:{command}, cwd}). Flag --less also reports ANY push/merge.
stdout: one line "KIND<TAB>reason". KIND: OK | MAIN (push/merge-equivalent to main/master,
or other protected-branch bypass) | PUSH | MERGE (only with --less) | ASK (cannot decide).
Fails closed: any internal error is reported as ASK.
Known limits: shell variables as command words, remote.<n>.push config, ssh/remote shells.
"""
import json, os, re, shlex, subprocess, sys

PROT = {"main", "master"}
RE_ENV = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\+?=")
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
WRAP_ARG = {"xargs": {"-I", "-n", "-P", "-d", "-L", "-E", "-a", "-s"}, "sudo": {"-u", "-g", "-h", "-p", "-C", "-D", "-R", "-T", "-U"},
            "doas": {"-u"}, "nice": {"-n"}, "stdbuf": {"-i", "-o", "-e"}, "timeout": {"-s", "-k"}, "watch": {"-n"}}
WRAP = {"command", "builtin", "exec", "nohup", "time", "setsid", "!", "{", "then", "do", "else", "elif", "if", "while", "until",
        "sudo", "doas", "stdbuf", "nice", "timeout", "xargs", "watch"}
KNOWN = set("add am archive bisect blame branch bundle checkout cherry-pick clean clone commit config describe diff fetch format-patch "
            "gc grep init log merge mv notes pull push rebase reflog remote reset restore revert rm show stash status submodule switch "
            "tag worktree rev-parse rev-list ls-files ls-remote apply cat-file update-ref symbolic-ref maintenance help version".split())
CUR_SUBST = re.compile(r"\$\(\s*git\s+(branch\s+--show-current|rev-parse\s+--abbrev-ref\s+HEAD)\s*\)")
API_PAT = [re.compile(p) for p in (r"/merges$", r"/pulls/[^/]+/merge$", r"/pulls/[^/]+/update-branch$",
                                   r"/branches/[^/]+/(rename|merge)", r"/protection|/rulesets")]
GQL_DENY = re.compile(r"mergePullRequest|mergeBranch|enablePullRequestAutoMerge")
GQL_ASK = re.compile(r"createCommitOnBranch|updateRef|deleteRef")
CUR = "__CUR__"


class Ctx:
    def __init__(self, cwd, less):
        self.cwd, self.less, self.found = cwd, less, []

    def add(self, kind, why):
        self.found.append((kind, why.replace('"', "'").replace("\\", "/")))


def git_out(cwd, gitdir, *a):
    env = dict(os.environ)
    if gitdir:
        env["GIT_DIR"] = gitdir
    try:
        r = subprocess.run(["git", *a], cwd=cwd, env=env, capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def split_segments(s):
    segs, cur, q, i = [], [], None, 0
    while i < len(s):
        c = s[i]
        if q:
            cur.append(c)
            if c == "\\" and q == '"' and i + 1 < len(s):
                cur.append(s[i + 1]); i += 1
            elif c == q:
                q = None
        elif c == "\\" and i + 1 < len(s):
            cur.append(c); cur.append(s[i + 1]); i += 1
        elif c in "'\"":
            q = c; cur.append(c)
        elif c in ";&|()\n`":
            segs.append("".join(cur)); cur = []
        else:
            cur.append(c)
        i += 1
    if q:
        raise ValueError("unterminated quote")
    segs.append("".join(cur))
    return [x for x in segs if x.strip()]


def scan(cmd, ctx, depth):
    if depth > 6:
        raise ValueError("nesting too deep")
    cmd = CUR_SUBST.sub(CUR, cmd)
    for inner in re.findall(r"\$\(([^()]*)\)", cmd) + re.findall(r"`([^`]*)`", cmd):
        if depth < 6 and inner.strip() and inner != cmd:
            scan(inner, ctx, depth + 1)
    for seg in split_segments(cmd):
        words = [w for w in shlex.split(seg) if not re.match(r"^\d*[<>]+&?\d*$", w)]
        handle(words, ctx, depth)


def strip_wrap(b, rest):
    take = WRAP_ARG.get(b, set())
    while rest and rest[0].startswith("-") and rest[0] != "--":
        rest = rest[2:] if rest[0] in take else rest[1:]
    if rest and rest[0] == "--":
        rest = rest[1:]
    if b in ("timeout",) and rest:
        rest = rest[1:]  # duration
    return rest


def strip_env(rest, env):
    while rest and rest[0].startswith("-"):
        t = rest[0]
        if t == "--":
            rest = rest[1:]; break
        if t in ("-u", "-C", "--chdir", "--unset"):
            rest = rest[2:]
        elif t in ("-S", "--split-string") and len(rest) > 1:
            rest = shlex.split(rest[1]) + rest[2:]
        else:
            rest = rest[1:]
    return rest


def handle(w, ctx, depth):
    env = {}
    while w:
        t = w[0]
        b = os.path.basename(t)
        b = b[:-4] if b.endswith(".exe") else b
        if RE_ENV.match(t):
            k, _, v = t.partition("="); env[k] = v; w = w[1:]
        elif b in ("cd", "pushd"):
            tgt = os.path.expanduser(w[1]) if len(w) > 1 else None
            if tgt and "$" not in tgt and tgt != "-":
                ctx.cwd = tgt if os.path.isabs(tgt) else os.path.join(ctx.cwd, tgt)
            return
        elif b in ("git", "gh"):
            (do_git if b == "git" else do_gh)(w[1:], env, ctx, depth)
            return
        elif b in SHELLS:
            for i, a in enumerate(w[1:], 1):
                if a.startswith("-") and not a.startswith("--") and "c" in a:
                    if i + 1 >= len(w):
                        raise ValueError("shell -c without body")
                    scan(w[i + 1], ctx, depth + 1)
                    break
            return
        elif b == "eval":
            scan(" ".join(w[1:]), ctx, depth + 1); return
        elif b == "env":
            w = strip_env(w[1:], env)
        elif b in WRAP:
            w = strip_wrap(b, w[1:])
        else:
            if ("$" in t) and any(x in ("push", "merge") for x in w[1:]):
                ctx.add("ASK", "command word is a shell variable next to push/merge")
            return


def resolve_cwd(base, d):
    d = os.path.expanduser(d)
    return d if os.path.isabs(d) else os.path.join(base, d)


COMMIT_VAL_OPTS = {"-m", "-F", "-C", "-c", "-t", "--message", "--file", "--reuse-message", "--reedit-message", "--template"}


def hook_env(env, ctx):
    if "SKIP" in env or "HUSKY" in env:
        ctx.add("HOOK", "SKIP=/HUSKY= env prefix skips git hooks")
    if any("hookspath" in v.lower() for k, v in env.items() if k == "GIT_CONFIG_PARAMETERS" or k.startswith("GIT_CONFIG_KEY_")):
        ctx.add("HOOK", "core.hooksPath set through GIT_CONFIG_* env")


def hook_args(sub, rest, ctx):
    skip = False
    for a in rest:
        if skip:
            skip = False; continue
        if a == "--":
            return
        if a.startswith("--no-v") and "--no-verify".startswith(a.split("=")[0]):
            ctx.add("HOOK", f"git {sub} {a} skips git hooks"); return
        if sub == "config" and a.lower().startswith("core.hookspath") and not {"--get", "--list", "-l"} & set(rest):
            ctx.add("HOOK", "git config core.hooksPath redirects git hooks"); return
        if sub != "commit":
            continue
        if a in COMMIT_VAL_OPTS:
            skip = True
        elif re.match(r"^-[A-Za-z]+$", a) and "n" in re.split(r"[umFCcSt]", a[1:], maxsplit=1)[0]:
            ctx.add("HOOK", f"git commit {a} (-n) skips git hooks"); return


def do_git(args, env, ctx, depth):
    cwd, gitdir, aliases, i = ctx.cwd, env.get("GIT_DIR"), {}, 0
    hook_env(env, ctx)
    while i < len(args) and args[i].startswith("-"):
        t = args[i]
        if t.startswith("-c") and len(t) > 2:
            args = args[:i] + ["-c", t[2:]] + args[i + 1:]; t = "-c"
        if t.startswith("--config-env="):
            args = args[:i] + ["--config-env", t.split("=", 1)[1]] + args[i + 1:]; t = "--config-env"
        if t in ("-c", "-C", "--git-dir", "--work-tree", "--namespace", "--super-prefix", "--config-env"):
            if i + 1 >= len(args):
                raise ValueError(f"git {t} missing value")
            v = args[i + 1]
            if t == "-C":
                cwd = resolve_cwd(cwd, v)
            elif t == "--git-dir":
                gitdir = v
            elif t in ("-c", "--config-env") and v.lower().startswith("core.hookspath"):
                ctx.add("HOOK", f"git {t} core.hooksPath redirects git hooks")
            elif t == "-c" and v.lower().startswith("alias."):
                k, _, val = v[6:].partition("="); aliases[k] = val
            i += 2
            continue
        if t.startswith("--git-dir="):
            gitdir = t.split("=", 1)[1]
        i += 1
    if i >= len(args):
        return
    sub, rest = args[i], args[i + 1:]
    if sub not in KNOWN:
        val = aliases.get(sub) or git_out(cwd, gitdir, "config", "--get", f"alias.{sub}")
        if val:
            if val.startswith("!"):
                scan(val[1:] + " " + " ".join(shlex.quote(r) for r in rest), ctx, depth + 1)
                return
            parts = shlex.split(val)
            sub, rest = (parts[0], parts[1:] + rest) if parts else (sub, rest)
    hook_args(sub, rest, ctx)
    if sub == "update-ref":
        refs = [a for a in rest if not a.startswith("-")]
        if refs and norm(refs[0]) in PROT:
            ctx.add("MAIN", f"git update-ref {refs[0]} rewrites main/master")
        return
    if sub != "push":
        return
    if ctx.less:
        ctx.add("PUSH", "git push")
    push_main(rest, cwd, gitdir, ctx)


def norm(d):
    d = d.strip()
    for p in ("refs/heads/", "heads/"):
        if d.startswith(p):
            d = d[len(p):]
    return d.lower()


ALLOW_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "push-main-allow.txt")


def main_allowed(cwd, gitdir):
    """Repos that commit straight to main by design, one absolute toplevel path per line."""
    top = git_out(cwd, gitdir, "rev-parse", "--show-toplevel")
    if not top or not os.path.isfile(ALLOW_FILE):
        return False
    with open(ALLOW_FILE) as f:
        allowed = {os.path.realpath(os.path.expanduser(l.strip())) for l in f if l.strip() and not l.startswith("#")}
    return os.path.realpath(top) in allowed


def push_main(args, cwd, gitdir, ctx):
    if main_allowed(cwd, gitdir):
        return
    pos, i, repo_flag = [], 0, False
    val_opts = {"-o", "--push-option", "--repo", "--receive-pack", "--exec", "--recurse-submodules"}
    while i < len(args):
        t = args[i]
        if t == "--":
            pos += args[i + 1:]; break
        if t.startswith("--"):
            name = t.split("=", 1)[0]
            if len(name) >= 4 and any(f.startswith(name) for f in ("--all", "--mirror")):
                ctx.add("MAIN", f"git push {name} touches main/master"); return
            repo_flag = repo_flag or name == "--repo"
            if name in val_opts and "=" not in t:
                i += 1
        elif t.startswith("-") and len(t) > 1:
            if t == "-o":
                i += 1
        else:
            pos.append(t)
        i += 1
    specs = pos if repo_flag else pos[1:]
    cur = git_out(cwd, gitdir, "rev-parse", "--abbrev-ref", "HEAD")
    pushbr = git_out(cwd, gitdir, "rev-parse", "--abbrev-ref", "@{push}")
    if not specs:
        if cur is None:
            ctx.add("ASK", "cannot resolve current branch for implicit push"); return
        cands = [cur] + ([pushbr.split("/", 1)[-1]] if pushbr else [])
        if any(norm(c) in PROT for c in cands):
            ctx.add("MAIN", f"implicit push resolves to protected branch ({'/'.join(cands)})")
        return
    for spec in specs:
        check_spec(spec, cur, ctx)


def check_spec(spec, cur, ctx):
    r = spec[1:] if spec.startswith("+") else spec
    if r == ":":
        ctx.add("MAIN", "matching-branches refspec ':' pushes main/master"); return
    dst = r.split(":", 1)[1] if ":" in r else r
    if dst in ("HEAD", "@") or (dst == CUR):
        if cur is None:
            ctx.add("ASK", "cannot resolve current branch for HEAD refspec"); return
        dst = cur
    if "*" in dst:
        ctx.add("MAIN", f"wildcard refspec '{spec}' can hit main/master"); return
    if re.search(r"[$`{?\[]", dst) or dst == "":
        ctx.add("ASK", f"unresolvable refspec '{spec}'"); return
    if norm(dst) in PROT:
        ctx.add("MAIN", f"push to protected branch via refspec '{spec}'")


def gh_parse(args):
    pos, fields, method, inp, i = [], {}, None, False, 0
    skip = {"-R", "--repo", "--hostname", "-H", "--header", "-q", "--jq", "-t", "--template", "--cache", "-p", "--preview"}
    while i < len(args):
        t = args[i]
        name, eq, val = t.partition("=") if t.startswith("--") else (t, "", "")
        if t.startswith("-") and t != "-":
            def nxt():
                return val if eq else (args[i + 1] if i + 1 < len(args) else "")
            used = 0 if eq else 1
            if name in ("-X", "--method"): method = nxt(); i += used
            elif name in ("-f", "-F", "--field", "--raw-field"):
                k, _, v = nxt().partition("="); fields[k] = v; i += used
            elif name == "--input": inp = True; i += used
            elif name in skip: i += used
            elif t.startswith("-X") and len(t) > 2: method = t[2:]
            elif t[:2] in ("-f", "-F") and len(t) > 2:
                k, _, v = t[2:].partition("="); fields[k] = v
        else:
            pos.append(t)
        i += 1
    return pos, fields, method, inp


def do_gh(args, env, ctx, depth):
    pos, fields, method, inp = gh_parse(args)
    if len(pos) >= 2 and pos[:2] == ["pr", "merge"]:
        if ctx.less:
            ctx.add("MERGE", "gh pr merge")
        if "--admin" in args:
            ctx.add("MAIN", "gh pr merge --admin bypasses branch protection")
        return
    if not pos or pos[0] != "api":
        return
    ep = (pos[1] if len(pos) > 1 else "").lstrip("/").lower()
    mut = (method.upper() != "GET") if method else bool(fields or inp)
    if ep == "graphql":
        text = " ".join(args)
        if GQL_DENY.search(text):
            ctx.add("MAIN", "gh api graphql merge mutation bypasses REVIEWED/CI gate")
        elif GQL_ASK.search(text):
            ctx.add("ASK", "gh api graphql ref/commit mutation")
        if ctx.less and (GQL_DENY.search(text) or GQL_ASK.search(text)):
            ctx.add("MERGE", "gh api graphql mutation")
        return
    if ctx.less and ("merge" in ep or (mut and re.search(r"/(contents|git/refs)", ep))):
        ctx.add("MERGE", "gh api merge/push equivalent")
    if not mut:
        return
    if "$" in ep:
        ctx.add("ASK", "gh api mutating call with variable endpoint"); return
    if any(p.search(ep) for p in API_PAT):
        ctx.add("MAIN", f"gh api {ep}: merge/protection write bypasses REVIEWED/CI gate")
    if "/contents/" in ep and norm(fields.get("branch", "main")) in PROT:
        ctx.add("MAIN", "gh api contents write commits directly to main/master")
    m = re.search(r"/git/refs/(?:heads/)?(.+)$", ep)
    ref = norm(m.group(1)) if m else norm(fields.get("ref", "")) if "/git/refs" in ep else ""
    if ref in PROT:
        ctx.add("MAIN", "gh api git/refs write targets main/master")


HEREDOC = re.compile(r"(?<!<)<<(-?)[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")
SHELL_FED = SHELLS | {"ssh", "eval", "source", "."}


def heredoc_runs_as_shell(line):
    """True when the body may run as shell: a shell is named on the line, or the line
    continues onto the next one (trailing pipe, && or backslash), where it may be named."""
    if re.search(r"(\||&&|\\)\s*$", line):
        return True
    bare = re.sub(r"'[^']*'|\"(?:\\.|[^\"\\])*\"", " ", line)
    return any(os.path.basename(w) in SHELL_FED for w in re.split(r"[\s;&|()`]+", bare))


def heredoc_ops(line):
    """Heredoc operators outside quotes and $((...)) arithmetic, in order."""
    ops, q, arith, i = [], "", 0, 0
    while i < len(line):
        c = line[i]
        if q:
            if c == "\\" and q == '"':
                i += 1
            elif c == q:
                q = ""
        elif c == "\\":
            i += 1
        elif c in "'\"":
            q = c
        elif c == "#" and (i == 0 or line[i - 1] in " \t;&|("):
            break
        elif line.startswith("((", i):
            arith += 1; i += 1
        elif line.startswith("))", i) and arith:
            arith -= 1; i += 1
        elif c == "<" and not arith:
            m = HEREDOC.match(line, i)
            if m and not line.startswith("<<<", i):
                ops.append(m)
                i = m.end(); continue
        i += 1
    return ops


def expansions(body):
    """Commands an unquoted heredoc body runs via $(...) or backticks. All of the body
    when nesting defeats the simple extraction, so nothing is hidden."""
    text = "\n".join(body)
    subs = re.findall(r"\$\(([^()]*)\)", text) + re.findall(r"`([^`]*)`", text)
    if text.count("$(") != len(re.findall(r"\$\([^()]*\)", text)):
        return body
    return [s for s in subs if s.strip()]


def strip_heredocs(cmd):
    """Drop heredoc bodies that are data (cat, tee, python...); keep bodies fed to a shell.
    An unquoted body keeps its command substitutions, which bash runs. A body whose
    terminator never appears is kept, so a fake marker cannot hide commands."""
    out, pending, body = [], [], []
    for line in cmd.split("\n"):
        if pending:
            delim, dash, keep, quoted = pending[0]
            if (line.lstrip("\t") if dash else line) == delim:
                pending.pop(0)
                out.extend(body if keep else [] if quoted else expansions(body))
                body = []
            else:
                body.append(line)
            continue
        out.append(line)
        for m in heredoc_ops(line):
            pending.append((m.group(3), m.group(1) == "-", heredoc_runs_as_shell(line), bool(m.group(2))))
    out.extend(body)
    return "\n".join(out)


def main():
    less = "--less" in sys.argv
    try:
        d = json.load(sys.stdin)
        cmd = strip_heredocs((d.get("tool_input") or {}).get("command") or "").replace("\\\n", "")
        if "--strip" in sys.argv:
            print(cmd)
            return
        ctx = Ctx(d.get("cwd") or os.getcwd(), less)
        scan(cmd, ctx, 0)
    except Exception as e:  # fail closed: reported as ASK, never silently passed
        print(f"ASK\tpush-guard could not parse command: {type(e).__name__}: {e}".replace('"', "'"))
        return
    for kind in ("MAIN", "HOOK", "PUSH", "MERGE", "ASK"):
        for k, why in ctx.found:
            if k == kind:
                print(f"{k}\t{why}"); return
    print("OK\t")


main()
