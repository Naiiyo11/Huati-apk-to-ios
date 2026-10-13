"""Package the unsigned source project; never include account files or signing material."""
from pathlib import Path
import hashlib
import json
import stat
import zipfile

ROOT = Path(__file__).resolve().parents[2]
IOS = ROOT / 'ios'
DIST = ROOT / 'dist'

def main():
    DIST.mkdir(exist_ok=True)
    output=DIST/'huati-assistant-ios-v2.0.4-xcode.zip'
    excluded={'Exports','__pycache__','xcuserdata','.DS_Store'}
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED,compresslevel=8) as archive:
        for source in sorted(IOS.rglob('*')):
            if not source.is_file() or any(p in excluded for p in source.relative_to(IOS).parts):continue
            relative='Huati-iOS-v2.0.4/'+source.relative_to(IOS).as_posix()
            item=zipfile.ZipInfo(relative)
            item.create_system=3
            item.external_attr=(stat.S_IFREG | (0o755 if source.suffix=='.command' else 0o644))<<16
            item.compress_type=zipfile.ZIP_DEFLATED
            archive.writestr(item,source.read_bytes())
    with zipfile.ZipFile(output) as archive:
        assert archive.testzip() is None
        names=archive.namelist()
        assert not any(name.lower().endswith(('.p12','.mobileprovision','.pem','.key','.ipa','.apk')) for name in names)
        assert not any('/private/' in name or name.endswith('/huati-session.json') for name in names)
        for name in names:
            item=archive.getinfo(name)
            if name.endswith('.command'):assert (item.external_attr>>16)&0o111
        assert 'Huati-iOS-v2.0.4/Huati.xcodeproj/project.pbxproj' in names
    digest=hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix('.zip.sha256').write_text(digest+'  '+output.name+'\n',encoding='ascii')
    record={'artifact':output.name,'bytes':output.stat().st_size,'sha256':digest,'files':len(names),'kind':'unsigned Xcode project; not installable IPA','minimum_ios':'17.0','compiled_in_xcode':False,'signed_ipa':False,'iphone_tested':False}
    (DIST/'huati-assistant-ios-v2.0.4-package.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(record))

if __name__=='__main__':main()
