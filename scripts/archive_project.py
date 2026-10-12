"""Local, verifiable source archive; never reads Keychain or follows symlinks."""
import hashlib, io, json, os, pathlib, re, sys, tarfile
from datetime import datetime
from zoneinfo import ZoneInfo

root = pathlib.Path(__file__).resolve().parent.parent
label = sys.argv[1] if len(sys.argv) > 1 else "snapshot"
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,90}", label):
    raise SystemExit("Use a short archive label with letters, numbers, dots or hyphens.")
now = datetime.now(ZoneInfo("Europe/Kiev"))
out = root / "archive" / (now.strftime("%Y%m%d-%H%M%S") + "-" + label + ".tar.gz")
out.parent.mkdir(exist_ok=True)
base = out; serial = 1
while out.exists():
    out = base.with_name(base.name.replace(".tar.gz", f"-{serial}.tar.gz")); serial += 1
excluded_dirs = {"archive", "build", ".build", ".git", "node_modules", "__pycache__", ".codex", ".agents"}
excluded_suffixes = {".p12", ".p8", ".pem", ".key", ".mobileprovision", ".xcuserstate", ".pyc"}
entries = []
for folder, dirs, files in os.walk(root, followlinks=False):
    dirs[:] = sorted(d for d in dirs if d not in excluded_dirs and d != "xcuserdata")
    links = [pathlib.Path(folder) / d for d in dirs if (pathlib.Path(folder) / d).is_symlink()]
    entries.extend(links)
    dirs[:] = [d for d in dirs if not (pathlib.Path(folder) / d).is_symlink()]
    for name in sorted(files):
        p = pathlib.Path(folder) / name
        if name == ".DS_Store" or name.startswith(".env") or p.suffix in excluded_suffixes:
            continue
        entries.append(p)
manifest = {"created_at": now.isoformat(), "label": label, "files": [],
            "excluded": sorted(excluded_dirs | {".env*", "credentials/certificates", "xcuserdata"})}
with tarfile.open(out, "w:gz") as tar:
    for p in entries:
        rel = p.relative_to(root).as_posix()
        if p.is_symlink():
            manifest["files"].append({"path": rel, "symlink": os.readlink(p)})
        else:
            manifest["files"].append({"path": rel, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()})
        tar.add(p, arcname=rel, recursive=False)
    data = json.dumps(manifest, ensure_ascii=False, indent=2).encode()
    item = tarfile.TarInfo("ARCHIVE_MANIFEST.json"); item.size = len(data); item.mode = 0o600
    tar.addfile(item, io.BytesIO(data))
os.chmod(out, 0o600)
# Verify bytes directly in the tarball, without extracting or executing anything.
with tarfile.open(out, "r:gz") as tar:
    for entry in manifest["files"]:
        if "sha256" in entry:
            assert hashlib.sha256(tar.extractfile(entry["path"]).read()).hexdigest() == entry["sha256"], entry["path"]
checksum = hashlib.sha256(out.read_bytes()).hexdigest()
out.with_suffix(out.suffix + ".sha256").write_text(checksum + "  " + out.name + "\n")
print(str(out.relative_to(root)), "verified", len(entries), "files", round(out.stat().st_size / 1024 / 1024, 2), "MiB")
