"""Host checks. This does not replace Xcode compilation or an iPhone device test."""
from pathlib import Path
import hashlib
import json
import os
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
IOS = ROOT / 'ios'
sys.path.insert(0, str(ROOT / '.toolchain/ios-validation'))
from tree_sitter import Language, Parser
import tree_sitter_swift
import tree_sitter_bash
from pbxproj import XcodeProject
from PIL import Image, ImageChops

def main():
    parser=Parser(Language(tree_sitter_swift.language()))
    issues=[]
    sources=sorted((IOS/'Huati').rglob('*.swift'))+sorted((IOS/'HuatiTests').rglob('*.swift'))
    for source in sources:
        raw=source.read_bytes();tree=parser.parse(raw)
        def visit(node):
            if node.type=='ERROR' or node.is_missing:issues.append({'file':str(source.relative_to(IOS)), 'line':node.start_point.row+1, 'fragment':raw[node.start_byte:node.end_byte].decode('utf-8','replace')[:180]})
            for child in node.children:visit(child)
        visit(tree.root_node)
    if issues:
        print(json.dumps({'swift_parse_errors':issues},ensure_ascii=False,indent=2));return 1
    shell_parser=Parser(Language(tree_sitter_bash.language()))
    for script in IOS.glob('*.command'):
        assert not shell_parser.parse(script.read_bytes()).root_node.has_error,script
    project=XcodeProject.load(str(IOS/'Huati.xcodeproj/project.pbxproj'))
    assert project is not None
    refs=project.objects.get_objects_in_section('PBXFileReference')
    for ref in refs:
        if ref.sourceTree=='<group>':assert (IOS/ref.path).exists(),ref.path
    schemes=list((IOS/'Huati.xcodeproj').rglob('*.xcscheme'))
    assert len(schemes)==1
    for path in schemes+list((IOS/'Huati.xcodeproj').rglob('*.xcworkspacedata'))+[IOS/'Huati/LaunchScreen.storyboard']:ET.parse(path)
    info=plistlib.loads((IOS/'Huati/Info.plist').read_bytes())
    assert set(info['BGTaskSchedulerPermittedIdentifiers'])=={'cn.huati.assistant.ios.run','cn.huati.assistant.ios.probe'}
    assert set(info['UIBackgroundModes'])=={'processing','fetch'}
    assert 'NSLocationAlwaysAndWhenInUseUsageDescription' not in info
    privacy=plistlib.loads((IOS/'Huati/PrivacyInfo.xcprivacy').read_bytes())
    assert not privacy['NSPrivacyTracking']
    assets=json.loads((IOS/'asset-manifest.json').read_text(encoding='utf-8'))
    for item in assets:
        output=IOS/item['output'];assert hashlib.sha256(output.read_bytes()).hexdigest()==item['sha256']
        Image.open(output).verify()
        if output.suffix=='.png':
            source=Image.open(ROOT/item['source']).convert('RGBA');converted=Image.open(output).convert('RGBA')
            assert source.size==converted.size and not ImageChops.difference(source,converted).getbbox(),output
    icons=json.loads((IOS/'Huati/Assets.xcassets/AppIcon.appiconset/Contents.json').read_text())
    for icon in icons['images']:
        image=Image.open(IOS/'Huati/Assets.xcassets/AppIcon.appiconset'/icon['filename'])
        assert image.mode=='RGB' and image.width==image.height
    assert len(list((IOS/'Huati/Resources/Art/wallpapers').glob('*.jpg')))==19
    assert len(list((IOS/'Huati/Resources/Art/mascots').glob('*.png')))==36
    assert len(list((IOS/'Huati/Resources/Art/backgrounds').glob('*.jpg')))==3
    assert (IOS/'Huati/Core/run-core.js').read_bytes()==(IOS/'Huati/Resources/Core/run-core.js').read_bytes()
    results=[]
    for timezone in ['UTC','Asia/Shanghai','America/Los_Angeles']:
        env={**os.environ,'TZ':timezone}
        process=subprocess.run(['node','--test',str(IOS/'Tests/core.test.cjs')],capture_output=True,text=True,encoding='utf-8',env=env)
        results.append({'timezone':timezone,'exit_code':process.returncode,'output':process.stdout+process.stderr})
        if process.returncode:print(results[-1]['output']);return 1
    report={'app':'华理跑步姬','version':'2.0.4','platform':'iOS','minimum_ios':'17.0','swift_files_parsed':len(sources),'swift_syntax_parser':'tree-sitter-swift; not Swift type checking','xcode_project_parsed':True,'mac_command_scripts_parsed':3,'asset_files_verified':len(assets),'core_tests':39,'test_timezones':['UTC','Asia/Shanghai','America/Los_Angeles'],'local_tests_passed':True,'native_xctest_run':False,'xcode_compiled':False,'signed_ipa_produced':False,'iphone_device_test':False,'live_account_requests':False,'limitations':['Windows host cannot compile/link/sign iOS app; Xcode build required on Mac.','iOS BGProcessingTask earliestBeginDate does not guarantee precise background start or submission.']}
    (IOS/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    (IOS/'core-test-results.txt').write_text('\n\n'.join('TZ='+r['timezone']+'\n'+r['output'] for r in results),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False));return 0

if __name__=='__main__':raise SystemExit(main())
