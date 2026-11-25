#!/usr/bin/env bash
set -euo pipefail

ROOT="$(readlink -f "${1:-$(dirname "$(dirname "$(readlink -f "$0")")")/..}")"
python3 - "$ROOT" <<'PYEOF'
import os
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
archived_repos = {"BedwarsRel"}
pruned_dirs = {
    ".git", "node_modules", "build", "dist", "target", "vendor",
    "knowledge", "archive", "archives", "generated", "references",
}
frozen_wiki = root / "HRPAuth-Wiki"
old_display = re.compile(r"(?<![A-Za-z])(?:HA|HRPAuth)(?![A-Za-z])")
old_readme = re.compile(
    r"HRPAuth Wiki|HA Wiki|HA ecosystem|HA 生态|HA platform|HA 平台|"
    r"HA desktop|HA 桌面|HA operators|HA priority|HA 优先|HA account|HA UUID|"
    r"HA Services|HA-Contract|HRPAuth core|HRPAuth 核心"
)
old_core_url = re.compile(r"CoreMatch/HRPAuth(?=\.git(?:[\s?#)]|$)|[/?#])")
old_wiki_url = re.compile(r"wiki\.mcnb\.dev/(?:HRPAuth|deploy/hrpauth)(?=[/?#\s)]|$)")
url = re.compile(r"(?:https?|ftp)://[^\s<>\"']+")
old_config_brand = re.compile(r"^\s*(?:name|from_name):\s*[\"']?HRPAuth[\"']?\s*(?:#.*)?$", re.M)
problems = []
repos = 0
files = 0

for dirpath, dirnames, filenames in os.walk(root):
    current = Path(dirpath)
    rel = current.relative_to(root)
    if ".git" in dirnames and len(rel.parts) <= 2 and current.name not in archived_repos:
        repos += 1
        dirnames.remove(".git")
        if current == frozen_wiki:
            for name in ("HRPAuth", "HASkinProxy", "WinnerProxy"):
                if name in dirnames:
                    dirnames.remove(name)
        dirnames[:] = [d for d in dirnames if d not in pruned_dirs]
        for filename in sorted(filenames):
            path = current / filename
            if filename.startswith("README") and filename.endswith(".md"):
                text = path.read_text(encoding="utf-8")
                visible = url.sub("", text)
                for number, line in enumerate(visible.splitlines(), 1):
                    if old_readme.search(line):
                        problems.append(f"{path.relative_to(root)}:{number}: legacy brand in current README: {line.strip()}")
                for number, line in enumerate(text.splitlines(), 1):
                    if old_core_url.search(line) or old_wiki_url.search(line):
                        problems.append(f"{path.relative_to(root)}:{number}: stale core/wiki URL")
                files += 1
            elif filename == "deploy-manifest.yaml":
                text = path.read_text(encoding="utf-8")
                for number, line in enumerate(text.splitlines(), 1):
                    match = re.match(r"\s*display_name:\s*(.+?)\s*$", line)
                    if match and old_display.search(match.group(1).strip("\"'")):
                        problems.append(f"{path.relative_to(root)}:{number}: legacy display_name: {match.group(1)}")
                files += 1
            elif path.suffix in {".yaml", ".yml", ".tmpl"} or filename.endswith(".example"):
                if "test" in filename.lower():
                    continue
                text = path.read_text(encoding="utf-8")
                for match in old_config_brand.finditer(text):
                    number = text.count("\n", 0, match.start()) + 1
                    problems.append(f"{path.relative_to(root)}:{number}: legacy default site/SMTP brand")
                files += 1
        workflow_dir = current / ".github" / "workflows"
        if workflow_dir.is_dir():
            for path in sorted(workflow_dir.glob("*.y*ml")):
                text = path.read_text(encoding="utf-8")
                for number, line in enumerate(text.splitlines(), 1):
                    if old_core_url.search(line) or old_wiki_url.search(line):
                        problems.append(f"{path.relative_to(root)}:{number}: stale core/wiki URL")
                files += 1
        site_config = current / "src" / "site.ts"
        if site_config.is_file():
            text = site_config.read_text(encoding="utf-8")
            for number, line in enumerate(text.splitlines(), 1):
                if old_core_url.search(line) or old_wiki_url.search(line):
                    problems.append(f"{site_config.relative_to(root)}:{number}: stale core/wiki URL")
            files += 1
        continue
    dirnames[:] = [d for d in dirnames if d not in pruned_dirs and d != ".git"]
    if len(rel.parts) > 2:
        dirnames[:] = []
        continue

index = root / "项目索引.md"
if index.exists():
    text = index.read_text(encoding="utf-8")
    for number, line in enumerate(text.splitlines(), 1):
        if "hrpauth/HRPAuth/" in line:
            problems.append(f"项目索引.md:{number}: stale Armorial repository path")

for problem in problems:
    print(f"PROBLEM: {problem}")
print(f"Armorial branding checked: {repos} repositories, {files} current files, problems: {len(problems)}")
sys.exit(1 if problems else 0)
PYEOF
