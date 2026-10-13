"""Produce an offline, unsigned Xcode project using the Android 2.0.4 art and maps."""
from pathlib import Path
import hashlib
import json
import plistlib
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
IOS = ROOT / 'ios'
APP = IOS / 'Huati'
RES = APP / 'Resources'
ASSETS = ROOT / 'android/app/src/main/assets'
DRAWABLE = ROOT / 'android/app/src/main/res/drawable-nodpi'

def prepare_resources():
    (RES / 'Core').mkdir(parents=True, exist_ok=True)
    shutil.copy2(APP / 'Core/run-core.js', RES / 'Core/run-core.js')
    for name in ('campus-map.json', 'campus-roads.json'):
        shutil.copy2(ASSETS / name, RES / name)
    manifest = []
    for source in sorted((ASSETS / 'art').rglob('*.webp')):
        rel = source.relative_to(ASSETS / 'art')
        photo = rel.parts[0] in ('wallpapers', 'backgrounds')
        target = RES / 'Art' / rel.with_suffix('.jpg' if photo else '.png')
        target.parent.mkdir(parents=True, exist_ok=True)
        image = Image.open(source)
        if photo: image.convert('RGB').save(target, quality=95, subsampling=0, optimize=True)
        else: image.convert('RGBA').save(target, optimize=True)
        manifest.append({'source': str(source.relative_to(ROOT)).replace('\\','/'), 'output': str(target.relative_to(IOS)).replace('\\','/'), 'width': image.width, 'height': image.height, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
    for name in ('brand_head', 'launcher_head', 'nav_running', 'nav_account'):
        source = DRAWABLE / (name + '.webp')
        target = RES / 'Art/icons' / (name + '.png')
        target.parent.mkdir(parents=True, exist_ok=True)
        Image.open(source).convert('RGBA').save(target, optimize=True)
        manifest.append({'source': str(source.relative_to(ROOT)).replace('\\','/'), 'output': str(target.relative_to(IOS)).replace('\\','/'), 'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
    (IOS / 'asset-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    license_folder = RES / 'Licenses'; license_folder.mkdir(exist_ok=True)
    (license_folder / 'README.txt').write_text('校园底图及道路：© OpenStreetMap contributors，ODbL 1.0。\nhttps://www.openstreetmap.org/copyright\nhttps://opendatacommons.org/licenses/odbl/1-0/\n\n人物插画与 Q 版图片由用户提供。几何壁纸由项目内 Blender 脚本生成。\n本移植版使用 iOS 系统字体，无需分发安卓字体。\n', encoding='utf-8')
    shutil.copy2(ROOT / 'android/campus-data/README.md', license_folder / 'campus-data.md')
    shutil.copy2(ROOT / 'campus-points.template.json', IOS / 'campus-points.template.json')

def prepare_icons():
    catalog = APP / 'Assets.xcassets'
    catalog.mkdir(exist_ok=True)
    (catalog / 'Contents.json').write_text('{"info":{"author":"xcode","version":1}}', encoding='utf-8')
    icons = catalog / 'AppIcon.appiconset'; icons.mkdir(exist_ok=True)
    base = Image.new('RGB', (1024,1024), '#ffffff')
    head = Image.open(DRAWABLE / 'launcher_head.webp').convert('RGBA')
    head.thumbnail((900,900), Image.Resampling.LANCZOS)
    base.paste(head, ((1024-head.width)//2,(1024-head.height)//2),head)
    items = []
    specifications = [('iphone','20x20','2x',40),('iphone','20x20','3x',60),('iphone','29x29','2x',58),('iphone','29x29','3x',87),('iphone','40x40','2x',80),('iphone','40x40','3x',120),('iphone','60x60','2x',120),('iphone','60x60','3x',180),('ipad','20x20','1x',20),('ipad','20x20','2x',40),('ipad','29x29','1x',29),('ipad','29x29','2x',58),('ipad','40x40','1x',40),('ipad','40x40','2x',80),('ipad','76x76','1x',76),('ipad','76x76','2x',152),('ipad','83.5x83.5','2x',167),('ios-marketing','1024x1024','1x',1024)]
    for idiom,size,scale,pixels in specifications:
        name=f'icon-{pixels}.png'
        base.resize((pixels,pixels),Image.Resampling.LANCZOS).save(icons/name)
        items.append({'idiom':idiom,'size':size,'scale':scale,'filename':name})
    (icons / 'Contents.json').write_text(json.dumps({'images':items,'info':{'version':1,'author':'xcode'}},indent=2),encoding='utf-8')
    logo=catalog/'LaunchLogo.imageset'; logo.mkdir(exist_ok=True)
    base.save(logo/'logo.png')
    (logo/'Contents.json').write_text('{"images":[{"idiom":"universal","filename":"logo.png"}],"info":{"version":1,"author":"xcode"}}',encoding='utf-8')

def write_configuration():
    info = {'CFBundleDisplayName':'华理跑步姬','CFBundleName':'Huati','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundlePackageType':'APPL','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','LSRequiresIPhoneOS':True,'UILaunchStoryboardName':'LaunchScreen','UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False},'UIBackgroundModes':['processing','fetch'],'BGTaskSchedulerPermittedIdentifiers':['cn.huati.assistant.ios.run','cn.huati.assistant.ios.probe'],'NSLocationWhenInUseUsageDescription':'用于读取当前校园位置并准备本次起点，位置不可用时可采用校内模拟起点。','UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait'],'UISupportedInterfaceOrientations~ipad':['UIInterfaceOrientationPortrait','UIInterfaceOrientationPortraitUpsideDown','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],'ITSAppUsesNonExemptEncryption':False}
    (APP/'Info.plist').write_bytes(plistlib.dumps(info,sort_keys=False))
    collected=[{'NSPrivacyCollectedDataType':kind,'NSPrivacyCollectedDataTypeLinked':True,'NSPrivacyCollectedDataTypeTracking':False,'NSPrivacyCollectedDataTypePurposes':['NSPrivacyCollectedDataTypePurposeAppFunctionality']} for kind in ['NSPrivacyCollectedDataTypePhoneNumber','NSPrivacyCollectedDataTypeUserID','NSPrivacyCollectedDataTypePreciseLocation','NSPrivacyCollectedDataTypeOtherUserContent']]
    privacy={'NSPrivacyTracking':False,'NSPrivacyTrackingDomains':[],'NSPrivacyCollectedDataTypes':collected,'NSPrivacyAccessedAPITypes':[{'NSPrivacyAccessedAPIType':'NSPrivacyAccessedAPICategorySystemBootTime','NSPrivacyAccessedAPITypeReasons':['35F9.1']}]}
    (APP/'PrivacyInfo.xcprivacy').write_bytes(plistlib.dumps(privacy,sort_keys=False))
    storyboard='''<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="23094" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" launchScreen="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES" initialViewController="launch">
<device id="retina6_12" orientation="portrait" appearance="light"/><dependencies><plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="23084"/><capability name="Safe area layout guides" minToolsVersion="9.0"/><capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/></dependencies>
<scenes><scene sceneID="scene"><objects><viewController id="launch" sceneMemberID="viewController"><view key="view" contentMode="scaleToFill" id="view"><rect key="frame" x="0.0" y="0.0" width="393" height="852"/><autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/><subviews><imageView clipsSubviews="YES" userInteractionEnabled="NO" contentMode="scaleAspectFit" image="LaunchLogo" translatesAutoresizingMaskIntoConstraints="NO" id="logo"><rect key="frame" x="148.5" y="378" width="96" height="96"/><constraints><constraint firstAttribute="width" constant="96" id="width"/><constraint firstAttribute="height" constant="96" id="height"/></constraints></imageView></subviews><viewLayoutGuide key="safeArea" id="safe"/><color key="backgroundColor" red="0.8627" green="0.9255" blue="0.9647" alpha="1" colorSpace="custom" customColorSpace="sRGB"/><constraints><constraint firstItem="logo" firstAttribute="centerX" secondItem="view" secondAttribute="centerX" id="cx"/><constraint firstItem="logo" firstAttribute="centerY" secondItem="view" secondAttribute="centerY" id="cy"/></constraints></view></viewController><placeholder placeholderIdentifier="IBFirstResponder" id="first" sceneMemberID="firstResponder"/></objects></scene></scenes><resources><image name="LaunchLogo" width="1024" height="1024"/></resources></document>'''
    (APP/'LaunchScreen.storyboard').write_text(storyboard,encoding='utf-8')

def project():
    def ident(name):return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
    objects={}
    def add(name,value):objects[ident(name)]=value;return ident(name)
    def ref(name,kind,folder='Huati'):
        return add('file:'+name,{'isa':'PBXFileReference','lastKnownFileType':kind,'path':folder+'/'+name,'sourceTree':'<group>'})
    app_sources=[p.relative_to(APP).as_posix() for p in sorted(APP.rglob('*.swift'))]
    source_refs=[ref(p,'sourcecode.swift') for p in app_sources]
    source_builds=[add('build:'+p,{'isa':'PBXBuildFile','fileRef':r}) for p,r in zip(app_sources,source_refs)]
    resource_specs=[('Resources','folder'),('Assets.xcassets','folder.assetcatalog'),('LaunchScreen.storyboard','file.storyboard'),('PrivacyInfo.xcprivacy','text.xml')]
    resource_refs=[ref(p,k) for p,k in resource_specs]
    resource_builds=[add('build:'+p,{'isa':'PBXBuildFile','fileRef':r}) for (p,k),r in zip(resource_specs,resource_refs)]
    info_ref=ref('Info.plist','text.plist.xml')
    test_ref=ref('HuatiTests.swift','sourcecode.swift','HuatiTests')
    test_build=add('build:test',{'isa':'PBXBuildFile','fileRef':test_ref})
    product=add('app-product',{'isa':'PBXFileReference','explicitFileType':'wrapper.application','includeInIndex':'0','path':'Huati.app','sourceTree':'BUILT_PRODUCTS_DIR'})
    test_product=add('test-product',{'isa':'PBXFileReference','explicitFileType':'wrapper.cfbundle','includeInIndex':'0','path':'HuatiTests.xctest','sourceTree':'BUILT_PRODUCTS_DIR'})
    source_group=add('sources',{'isa':'PBXGroup','children':source_refs,'name':'Sources','sourceTree':'<group>'})
    resource_group=add('resources',{'isa':'PBXGroup','children':resource_refs+[info_ref],'name':'Resources','sourceTree':'<group>'})
    test_group=add('tests',{'isa':'PBXGroup','children':[test_ref],'name':'Tests','sourceTree':'<group>'})
    products_group=add('products',{'isa':'PBXGroup','children':[product,test_product],'name':'Products','sourceTree':'<group>'})
    main_group=add('main',{'isa':'PBXGroup','children':[source_group,resource_group,test_group,products_group],'sourceTree':'<group>'})
    sources=add('source-phase',{'isa':'PBXSourcesBuildPhase','buildActionMask':'2147483647','files':source_builds,'runOnlyForDeploymentPostprocessing':'0'})
    resources=add('resource-phase',{'isa':'PBXResourcesBuildPhase','buildActionMask':'2147483647','files':resource_builds,'runOnlyForDeploymentPostprocessing':'0'})
    frameworks=add('framework-phase',{'isa':'PBXFrameworksBuildPhase','buildActionMask':'2147483647','files':[],'runOnlyForDeploymentPostprocessing':'0'})
    test_sources=add('test-source-phase',{'isa':'PBXSourcesBuildPhase','buildActionMask':'2147483647','files':[test_build],'runOnlyForDeploymentPostprocessing':'0'})
    test_frameworks=add('test-framework-phase',{'isa':'PBXFrameworksBuildPhase','buildActionMask':'2147483647','files':[],'runOnlyForDeploymentPostprocessing':'0'})
    def configuration_list(name,settings):
        ids=[]
        for config in ('Debug','Release'):
            values=dict(settings)
            values['SWIFT_OPTIMIZATION_LEVEL']='-Onone' if config=='Debug' else '-O'
            if config=='Debug':values['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
            ids.append(add(name+':'+config,{'isa':'XCBuildConfiguration','buildSettings':values,'name':config}))
        return add(name+':list',{'isa':'XCConfigurationList','buildConfigurations':ids,'defaultConfigurationIsVisible':'0','defaultConfigurationName':'Release'})
    common={'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','SWIFT_STRICT_CONCURRENCY':'minimal','ENABLE_TESTABILITY':'YES','GCC_C_LANGUAGE_STANDARD':'gnu17'}
    project_configs=configuration_list('project-config',common)
    app_configs=configuration_list('app-config',{'PRODUCT_BUNDLE_IDENTIFIER':'cn.huati.assistant.ios','PRODUCT_NAME':'$(TARGET_NAME)','CODE_SIGN_STYLE':'Automatic','INFOPLIST_FILE':'Huati/Info.plist','GENERATE_INFOPLIST_FILE':'NO','MARKETING_VERSION':'2.0.4','CURRENT_PROJECT_VERSION':'18','TARGETED_DEVICE_FAMILY':'1,2','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks'],'SWIFT_EMIT_LOC_STRINGS':'YES'})
    test_configs=configuration_list('test-config',{'PRODUCT_BUNDLE_IDENTIFIER':'cn.huati.assistant.ios.tests','PRODUCT_NAME':'$(TARGET_NAME)','CODE_SIGN_STYLE':'Automatic','GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/Huati.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Huati','BUNDLE_LOADER':'$(TEST_HOST)','TARGETED_DEVICE_FAMILY':'1,2','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks','@loader_path/Frameworks']})
    app_target=add('app-target',{'isa':'PBXNativeTarget','buildConfigurationList':app_configs,'buildPhases':[sources,frameworks,resources],'buildRules':[],'dependencies':[],'name':'Huati','productName':'Huati','productReference':product,'productType':'com.apple.product-type.application'})
    project_id=ident('project')
    proxy=add('test-proxy',{'isa':'PBXContainerItemProxy','containerPortal':project_id,'proxyType':'1','remoteGlobalIDString':app_target,'remoteInfo':'Huati'})
    dep=add('test-dependency',{'isa':'PBXTargetDependency','target':app_target,'targetProxy':proxy})
    test_target=add('test-target',{'isa':'PBXNativeTarget','buildConfigurationList':test_configs,'buildPhases':[test_sources,test_frameworks],'buildRules':[],'dependencies':[dep],'name':'HuatiTests','productName':'HuatiTests','productReference':test_product,'productType':'com.apple.product-type.bundle.unit-test'})
    add('project',{'isa':'PBXProject','attributes':{'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'1600','TargetAttributes':{app_target:{'CreatedOnToolsVersion':'16.0'},test_target:{'CreatedOnToolsVersion':'16.0','TestTargetID':app_target}}},'buildConfigurationList':project_configs,'compatibilityVersion':'Xcode 14.0','developmentRegion':'zh-Hans','hasScannedForEncodings':'0','knownRegions':['zh-Hans','en','Base'],'mainGroup':main_group,'productRefGroup':products_group,'projectDirPath':'','projectRoot':'','targets':[app_target,test_target]})
    def serialize(value,indent=0):
        pad='\t'*indent
        if isinstance(value,dict):return '{\n'+''.join(pad+'\t'+serialize(str(k))+' = '+serialize(v,indent+1)+';\n' for k,v in value.items())+pad+'}'
        if isinstance(value,list):return '(\n'+''.join(pad+'\t'+serialize(v,indent+1)+',\n' for v in value)+pad+')'
        return json.dumps(str(value),ensure_ascii=False)
    folder=IOS/'Huati.xcodeproj';folder.mkdir(exist_ok=True)
    data={'archiveVersion':'1','classes':{},'objectVersion':'56','objects':objects,'rootObject':project_id}
    (folder/'project.pbxproj').write_text('// !$*UTF8*$!\n'+serialize(data)+'\n',encoding='utf-8')
    scheme_folder=folder/'xcshareddata/xcschemes';scheme_folder.mkdir(parents=True,exist_ok=True)
    scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="Huati.app" BlueprintName="Huati" ReferencedContainer="container:Huati.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_target}" BuildableName="HuatiTests.xctest" BlueprintName="HuatiTests" ReferencedContainer="container:Huati.xcodeproj"/></TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="Huati.app" BlueprintName="Huati" ReferencedContainer="container:Huati.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="Huati.app" BlueprintName="Huati" ReferencedContainer="container:Huati.xcodeproj"/></BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>'''
    (scheme_folder/'Huati.xcscheme').write_text(scheme,encoding='utf-8')
    workspace=folder/'project.xcworkspace';workspace.mkdir(exist_ok=True)
    (workspace/'contents.xcworkspacedata').write_text('<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><FileRef location="self:"/></Workspace>',encoding='utf-8')

if __name__=='__main__':
    prepare_resources();prepare_icons();write_configuration();project()
    print(json.dumps({'project':'ios/Huati.xcodeproj','swift_files':len(list(APP.rglob('*.swift'))),'art_files':len(list((RES/'Art').rglob('*.*'))),'asset_bytes':sum(p.stat().st_size for p in RES.rglob('*') if p.is_file())}))
