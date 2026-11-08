import plistlib,sys
from pathlib import Path
root=Path(__file__).resolve().parent.parent
info=plistlib.loads((root/'Config/App-Info.plist').read_bytes())
info.update(CFBundleIdentifier='com.stickeynote.app.preview',CFBundleExecutable='StickeyNote',StickeyCloudKitEnabled=False)
(Path(sys.argv[1])/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
