"""Package only the runtime files referenced by the addon TOC."""
from pathlib import Path
import re
import zipfile

ADDON = Path(__file__).resolve().parents[1]
TOC = ADDON / "QFXTalents.toc"
text = TOC.read_text(encoding="utf-8-sig")
version = re.search(r"^## Version: (\d+\.\d+\.\d+)$", text, re.MULTILINE).group(1)
members = [TOC] + [ADDON / line.strip() for line in text.splitlines()
                   if line.strip() and not line.startswith("#")]
for path in members:
    if not path.is_file() or path.parent != ADDON:
        raise RuntimeError(f"Invalid runtime file: {path.name}")
output = ADDON.parent / "releases" / f"QFXTalents_{version}.zip"
output.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in members:
        archive.write(path, f"QFXTalents/{path.name}")
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
    assert len(archive.namelist()) == len(members)
print(output)
print(f"{len(members)} runtime files; {output.stat().st_size} bytes")
