#!/usr/bin/env python3
"""Generate a dependency-free Xcode project; safe to rerun when adding sources."""
from pathlib import Path
import hashlib, json

ROOT = Path(__file__).resolve().parent.parent
objects = {}
def ident(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def put(name, value):
    key = ident(name); objects[key] = value; return key
def quote(value): return json.dumps(str(value))
def encode(value, depth=0):
    if isinstance(value, dict): return '{\n' + ''.join('\t'*(depth+1)+str(k)+' = '+encode(v,depth+1)+';\n' for k,v in value.items()) + '\t'*depth+'}'
    if isinstance(value, list): return '(' + ', '.join(encode(v,depth) for v in value) + ')'
    return quote(value)

app_sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT/'Sources/StickeyNote').rglob('*.swift'))
widget_sources = ['Widgets/StickeyNoteWidget.swift','Sources/StickeyNote/Integrations/WidgetSnapshot.swift']
refs = {}
for path in sorted(set(app_sources + widget_sources)):
    refs[path] = put('file:'+path, {'isa':'PBXFileReference','lastKnownFileType':'sourcecode.swift','path':path,'sourceTree':'SOURCE_ROOT'})
assets = put('assets',{'isa':'PBXFileReference','lastKnownFileType':'folder.assetcatalog','path':'Assets.xcassets','sourceTree':'SOURCE_ROOT'})
app_product = put('app-product',{'isa':'PBXFileReference','explicitFileType':'wrapper.application','path':'StickeyNote.app','sourceTree':'BUILT_PRODUCTS_DIR'})
preview_product = put('preview-product',{'isa':'PBXFileReference','explicitFileType':'wrapper.application','path':'Stickey Notes.app','sourceTree':'BUILT_PRODUCTS_DIR'})
widget_product = put('widget-product',{'isa':'PBXFileReference','explicitFileType':'wrapper.app-extension','path':'StickeyNoteWidget.appex','sourceTree':'BUILT_PRODUCTS_DIR'})
products = put('products',{'isa':'PBXGroup','children':[app_product,widget_product,preview_product],'name':'Products','sourceTree':'<group>'})
main = put('main',{'isa':'PBXGroup','children':list(refs.values())+[assets,products],'sourceTree':'<group>'})
package = put('package',{'isa':'XCLocalSwiftPackageReference','relativePath':'.'})
core = put('core-product',{'isa':'XCSwiftPackageProductDependency','package':package,'productName':'StickeyCore'})
core_build = put('core-link',{'isa':'PBXBuildFile','productRef':core})

def config_list(prefix, settings):
    configurations=[]
    for mode in ['Debug','Release']:
        config=dict(settings)
        config.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if mode=='Debug' else 'dwarf-with-dsym'})
        if mode=='Debug': config['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
        configurations.append(put(prefix+mode,{'isa':'XCBuildConfiguration','buildSettings':config,'name':mode}))
    return put(prefix+'configs',{'isa':'XCConfigurationList','buildConfigurations':configurations,'defaultConfigurationIsVisible':'0','defaultConfigurationName':'Release'})

common={'SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','MACOSX_DEPLOYMENT_TARGET':'14.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'auto','SUPPORTED_PLATFORMS':'macosx iphoneos iphonesimulator','TARGETED_DEVICE_FAMILY':'1,2','CODE_SIGN_STYLE':'Automatic','DEVELOPMENT_TEAM':'9KKZQH4QSC','CURRENT_PROJECT_VERSION':'1','MARKETING_VERSION':'1.0','ENABLE_USER_SCRIPT_SANDBOXING':'YES'}
proj_configs=config_list('project-',common)
app_settings={'PRODUCT_NAME':'StickeyNote','PRODUCT_BUNDLE_IDENTIFIER':'com.stickeynote.app','INFOPLIST_FILE':'Config/App-Info.plist','CODE_SIGN_ENTITLEMENTS':'Config/StickeyNote.entitlements','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','ENABLE_APP_SANDBOX':'YES','SWIFT_EMIT_LOC_STRINGS':'YES','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks','@executable_path/../Frameworks']}
preview_settings={**app_settings,'PRODUCT_NAME':'Stickey Notes','EXECUTABLE_NAME':'StickeyNote','PRODUCT_BUNDLE_IDENTIFIER':'com.stickeynote.app.preview','INFOPLIST_FILE':'Config/Preview-Info.plist','CODE_SIGN_ENTITLEMENTS':'Config/StickeyNotePreview.entitlements','ENABLE_APP_SANDBOX':'NO','SDKROOT':'macosx','SUPPORTED_PLATFORMS':'macosx','CODE_SIGN_IDENTITY':'Apple Development','DEVELOPMENT_TEAM':'8ZA2YW2U9D','MARKETING_VERSION':'1.0.0','ENABLE_HARDENED_RUNTIME':'YES'}
widget_settings={'PRODUCT_NAME':'StickeyNoteWidget','PRODUCT_BUNDLE_IDENTIFIER':'com.stickeynote.app.widgets','INFOPLIST_FILE':'Widgets/Info.plist','GENERATE_INFOPLIST_FILE':'YES','CODE_SIGN_ENTITLEMENTS':'Widgets/StickeyNoteWidget.entitlements','APPLICATION_EXTENSION_API_ONLY':'YES','SKIP_INSTALL':'YES','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/../../Frameworks','@executable_path/../../../../Frameworks']}

def sources_phase(prefix,paths):
    files=[put(prefix+'build:'+path,{'isa':'PBXBuildFile','fileRef':refs[path]}) for path in paths]
    return put(prefix+'sources',{'isa':'PBXSourcesBuildPhase','buildActionMask':'2147483647','files':files,'runOnlyForDeploymentPostprocessing':'0'})

widget_target=put('widget-target',{'isa':'PBXNativeTarget','buildConfigurationList':config_list('widget-',widget_settings),'buildPhases':[sources_phase('widget-',widget_sources)],'buildRules':[],'dependencies':[],'name':'StickeyNoteWidget','productName':'StickeyNoteWidget','productReference':widget_product,'productType':'com.apple.product-type.app-extension'})
dependency=put('widget-dependency',{'isa':'PBXTargetDependency','target':widget_target})
embed_file=put('widget-embed-file',{'isa':'PBXBuildFile','fileRef':widget_product,'settings':{'ATTRIBUTES':['RemoveHeadersOnCopy']}})
embed=put('embed',{'isa':'PBXCopyFilesBuildPhase','buildActionMask':'2147483647','dstPath':'','dstSubfolderSpec':'13','files':[embed_file],'name':'Embed App Extensions','runOnlyForDeploymentPostprocessing':'0'})
frameworks=put('frameworks',{'isa':'PBXFrameworksBuildPhase','buildActionMask':'2147483647','files':[core_build],'runOnlyForDeploymentPostprocessing':'0'})
asset_build=put('asset-build',{'isa':'PBXBuildFile','fileRef':assets})
resources=put('resources',{'isa':'PBXResourcesBuildPhase','buildActionMask':'2147483647','files':[asset_build],'runOnlyForDeploymentPostprocessing':'0'})
app_target=put('app-target',{'isa':'PBXNativeTarget','buildConfigurationList':config_list('app-',app_settings),'buildPhases':[sources_phase('app-',app_sources),frameworks,resources,embed],'buildRules':[],'dependencies':[dependency],'name':'StickeyNote','packageProductDependencies':[core],'productName':'StickeyNote','productReference':app_product,'productType':'com.apple.product-type.application'})
# Keep the local Mac app's existing identity and storage location. Its only
# provisioned capability is Keychain access; CloudKit/widgets belong to the full app.
preview_core=put('preview-core-product',{'isa':'XCSwiftPackageProductDependency','package':package,'productName':'StickeyCore'})
preview_core_build=put('preview-core-link',{'isa':'PBXBuildFile','productRef':preview_core})
preview_frameworks=put('preview-frameworks',{'isa':'PBXFrameworksBuildPhase','buildActionMask':'2147483647','files':[preview_core_build],'runOnlyForDeploymentPostprocessing':'0'})
preview_asset=put('preview-asset-build',{'isa':'PBXBuildFile','fileRef':assets})
preview_resources=put('preview-resources',{'isa':'PBXResourcesBuildPhase','buildActionMask':'2147483647','files':[preview_asset],'runOnlyForDeploymentPostprocessing':'0'})
preview_target=put('preview-target',{'isa':'PBXNativeTarget','buildConfigurationList':config_list('preview-',preview_settings),'buildPhases':[sources_phase('preview-',app_sources),preview_frameworks,preview_resources],'buildRules':[],'dependencies':[],'name':'StickeyNotePreview','packageProductDependencies':[preview_core],'productName':'Stickey Notes','productReference':preview_product,'productType':'com.apple.product-type.application'})
project=put('project',{'isa':'PBXProject','attributes':{'BuildIndependentTargetsInParallel':'YES','LastSwiftUpdateCheck':'2600','LastUpgradeCheck':'2600','TargetAttributes':{preview_target:{'ProvisioningStyle':'Automatic','SystemCapabilities':{'com.apple.Keychain':{'enabled':'1'}}}}},'buildConfigurationList':proj_configs,'compatibilityVersion':'Xcode 14.0','developmentRegion':'en','hasScannedForEncodings':'0','knownRegions':['en','Base'],'mainGroup':main,'packageReferences':[package],'productRefGroup':products,'projectDirPath':'','projectRoot':'','targets':[app_target,widget_target,preview_target]})
out=ROOT/'StickeyNote.xcodeproj'; out.mkdir(exist_ok=True)
(out/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode({'archiveVersion':'1','classes':{},'objectVersion':'56','objects':objects,'rootObject':project})+'\n')
scheme_dir=out/'xcshareddata/xcschemes';scheme_dir.mkdir(parents=True,exist_ok=True)
ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="StickeyNote.app" BlueprintName="StickeyNote" ReferencedContainer="container:StickeyNote.xcodeproj"/>'
(scheme_dir/'StickeyNote.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug"/><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
preview_ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{preview_target}" BuildableName="Stickey Notes.app" BlueprintName="StickeyNotePreview" ReferencedContainer="container:StickeyNote.xcodeproj"/>'
(scheme_dir/'StickeyNotePreview.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{preview_ref}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug"/><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{preview_ref}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"><BuildableProductRunnable runnableDebuggingMode="0">{preview_ref}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print('Generated',out)
