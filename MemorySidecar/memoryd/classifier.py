from __future__ import annotations

import hashlib
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ProjectIdentity:
    project_id: str
    root: str
    remote: str | None
    head: str | None


@dataclass(frozen=True)
class ModuleIdentity:
    module_id: str
    name: str
    kind: str
    root_path: str


def detect_project(path: str | Path) -> ProjectIdentity:
    root = _git(["rev-parse", "--show-toplevel"], cwd=Path(path)) or str(Path(path).resolve())
    root_path = Path(root).resolve()
    remote = _git(["config", "--get", "remote.origin.url"], cwd=root_path)
    head = _git(["rev-parse", "HEAD"], cwd=root_path)
    raw = f"{_normalize_remote(remote) or ''}|{root_path}"
    project_id = hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]
    if remote:
        owner_repo = _owner_repo(remote)
        if owner_repo:
            project_id = owner_repo.replace("/", ":")
    return ProjectIdentity(project_id=project_id, root=str(root_path), remote=remote, head=head)


def detect_modules(root: str | Path) -> list[ModuleIdentity]:
    root_path = Path(root).resolve()
    modules: list[ModuleIdentity] = []
    project_yml = root_path / "project.yml"
    if project_yml.exists():
        modules.extend(_xcodegen_targets(root_path, project_yml))
    for manifest in ("Package.swift", "package.json", "pyproject.toml", "Cargo.toml", "go.mod"):
        if (root_path / manifest).exists():
            modules.append(_module("manifest", root_path.name, "."))
    if not modules:
        for child in root_path.iterdir():
            if child.is_dir() and not child.name.startswith(".") and child.name not in {"ThirdParty", "DerivedData"}:
                modules.append(_module("directory", child.name, child.name))
    seen: set[str] = set()
    unique: list[ModuleIdentity] = []
    for module in modules:
        if module.module_id in seen:
            continue
        seen.add(module.module_id)
        unique.append(module)
    return unique


def classify_path(root: str | Path, path: str | Path) -> dict[str, str]:
    root_path = Path(root).resolve()
    target = Path(path)
    if not target.is_absolute():
        target = root_path / target
    try:
        relative = target.resolve().relative_to(root_path)
    except ValueError:
        relative = target
    kind = "dir" if target.is_dir() else "file"
    return {"kind": kind, "path": str(relative)}


def _xcodegen_targets(root: Path, project_yml: Path) -> list[ModuleIdentity]:
    modules: list[ModuleIdentity] = []
    in_targets = False
    for line in project_yml.read_text(encoding="utf-8").splitlines():
        if line.startswith("targets:"):
            in_targets = True
            continue
        if not in_targets:
            continue
        if line and not line.startswith(" "):
            break
        if line.startswith("  ") and not line.startswith("    ") and line.strip().endswith(":"):
            name = line.strip()[:-1]
            modules.append(_module("xcode-target", name, name if (root / name).exists() else "."))
    return modules


def _module(kind: str, name: str, root_path: str) -> ModuleIdentity:
    safe = name.strip().replace(" ", "-")
    return ModuleIdentity(module_id=f"{kind}:{safe}:{root_path}", name=name, kind=kind, root_path=root_path)


def _git(args: list[str], *, cwd: Path) -> str | None:
    try:
        result = subprocess.run(["git", *args], cwd=cwd, check=False, capture_output=True, text=True, timeout=2)
    except Exception:
        return None
    value = result.stdout.strip()
    return value or None


def _normalize_remote(remote: str | None) -> str | None:
    if not remote:
        return None
    value = remote.strip()
    if value.startswith("git@github.com:"):
        value = "https://github.com/" + value.removeprefix("git@github.com:")
    if value.endswith(".git"):
        value = value[:-4]
    return value.lower()


def _owner_repo(remote: str) -> str | None:
    normalized = _normalize_remote(remote)
    if not normalized:
        return None
    marker = "github.com/"
    if marker not in normalized:
        return None
    return normalized.split(marker, 1)[1]
