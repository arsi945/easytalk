#!/usr/bin/env python3
"""Generate the Xcode project (app + keyboard extension) without XcodeGen/CocoaPods. Runs on macOS and Windows."""
import hashlib
import json
import pathlib
import plistlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent
# Keep the direct iPhone prompt identical to the server prompt.
# newline="\n": the same bytes on macOS and Windows.
(ROOT / "Shared" / "AnalysisPrompt.swift").write_text("// Generated from prompts/analyze_translate.md.\nlet analysisPrompt = " +
    json.dumps((ROOT.parent / "prompts" / "analyze_translate.md").read_text(encoding="utf-8"), ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
(ROOT / "Shared" / "ContextExportPrompt.swift").write_text("// Generated from prompts/context_export.md.\nlet contextExportPrompt = " +
    json.dumps((ROOT.parent / "prompts" / "context_export.md").read_text(encoding="utf-8"), ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
(ROOT / "Shared" / "StudyActionsPrompt.swift").write_text("// Generated from prompts/study_actions.md.\nlet studyActionsPrompt = " + json.dumps((ROOT.parent / "prompts" / "study_actions.md").read_text(encoding="utf-8"), ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
objects = {}

def read_pbxproj(path):
    """plutil on macOS; elsewhere parse the subset of the old-style plist that encode() below writes."""
    try:
        return json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(path)]))
    except FileNotFoundError:
        pass
    tokens = re.findall(r'"(?:[^"\\]|\\.)*"|[{}()=;,]|[^\s{}()=;,"]+', path.read_text(encoding="utf-8").split("\n", 1)[1])
    position = 0
    def value():
        nonlocal position
        token = tokens[position]; position += 1
        if token == "{":
            result = {}
            while tokens[position] != "}":
                key = value(); assert tokens[position] == "="; position += 1
                result[key] = value(); assert tokens[position] == ";"; position += 1
            position += 1
            return result
        if token == "(":
            result = []
            while tokens[position] != ")":
                result.append(value())
                if tokens[position] == ",": position += 1
            position += 1
            return result
        return json.loads(token) if token.startswith('"') else token
    return value()

# Retain user-selected signing when regenerating an existing project.
saved_signing = {}
project_file = ROOT / "EasyTalk.xcodeproj" / "project.pbxproj"
if project_file.exists():
    previous = read_pbxproj(project_file)["objects"]
    for target in previous.values():
        if target.get("isa") != "PBXNativeTarget": continue
        config_list = previous[target["buildConfigurationList"]]
        for ref in config_list["buildConfigurations"]:
            config = previous[ref]
            saved_signing[(target["name"], config["name"])] = {k: v for k, v in config["buildSettings"].items()
                if k in ["DEVELOPMENT_TEAM", "PRODUCT_BUNDLE_IDENTIFIER", "CODE_SIGN_STYLE", "CODE_SIGN_IDENTITY", "PROVISIONING_PROFILE_SPECIFIER"]}

def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def obj(object_key, isa, **fields):
    ident = uid(object_key)
    objects[ident] = dict(isa=isa, **fields)
    return ident

def file(path, kind="sourcecode.swift"):
    return obj(path, "PBXFileReference", lastKnownFileType=kind, path=path, sourceTree="<group>")

app_source = file("EasyTalk/AppDelegate.swift")
keyboard_source = file("Keyboard/KeyboardViewController.swift")
settings = file("Shared/ConnectionSettings.swift")
shared_storage = file("Shared/SharedStorage.swift")
input_history = file("Shared/InputHistory.swift")
context_export = file("Shared/ContextExport.swift")
context_prompt = file("Shared/ContextExportPrompt.swift")
history_screen = file("EasyTalk/HistoryViewController.swift")
contracts = file("../Sources/EasyTalkCore/Contracts.swift")
learning = file("../Sources/EasyTalkCore/Learning.swift")
learning_store = file("Shared/LearningStore.swift")
cursor_navigation = file("../Sources/EasyTalkCore/CursorNavigation.swift")
typing_rules = file("../Sources/EasyTalkCore/TypingRules.swift")
word_suggestions = file("../Sources/EasyTalkCore/WordSuggestions.swift")
suggestion_bar = file("Keyboard/SuggestionBar.swift")
keyboard_preferences = file("Shared/KeyboardPreferences.swift")
study_practice = file("Shared/StudyPractice.swift")
study_content = file("../Sources/EasyTalkCore/StudyContent.swift")
study_action = file("Shared/StudyActionService.swift")
study_prompt = file("Shared/StudyActionsPrompt.swift")
speech = file("Shared/SpeechPlayer.swift")
study_pager = file("Keyboard/StudyPagingView.swift")
idiom_catalog = file("../Sources/EasyTalkCore/IdiomCatalog.swift")
second_skill = file("Shared/SecondSkillCards.swift")
app_theme = file("Shared/EasyTalkTheme.swift")
document_bridge = file("Shared/DocumentProxyBridge.m", "sourcecode.c.objc")
document_bridge_header = file("Shared/DocumentProxyBridge.h", "sourcecode.c.h")
bridging_header = file("Shared/EasyTalkBridging.h", "sourcecode.c.h")
analysis_service = file("Shared/AnalysisService.swift")
keyboard_key = file("Keyboard/KeyboardKey.swift")
analysis_prompt = file("Shared/AnalysisPrompt.swift")
app_info = file("EasyTalk/Info.plist", "text.plist.xml")
app_entitlements = file("EasyTalk/EasyTalk.entitlements", "text.plist.entitlements")
keyboard_entitlements = file("Keyboard/EasyTalkKeyboard.entitlements", "text.plist.entitlements")
app_assets = file("EasyTalk/Assets.xcassets", "folder.assetcatalog")
keyboard_info = file("Keyboard/Info.plist", "text.plist.xml")
app_product = obj("app-product", "PBXFileReference", explicitFileType="wrapper.application", path="EasyTalk.app", sourceTree="BUILT_PRODUCTS_DIR")
keyboard_product = obj("keyboard-product", "PBXFileReference", explicitFileType="wrapper.app-extension", path="EasyTalkKeyboard.appex", sourceTree="BUILT_PRODUCTS_DIR")
products = obj("products", "PBXGroup", children=[app_product, keyboard_product], name="Products", sourceTree="<group>")
main = obj("main", "PBXGroup", children=[app_source, history_screen, keyboard_source, settings, shared_storage, input_history, context_export, context_prompt, contracts, learning, learning_store, cursor_navigation, typing_rules, word_suggestions, suggestion_bar, keyboard_preferences, study_practice, second_skill, idiom_catalog, study_content, study_action, study_prompt, speech, app_theme, document_bridge, document_bridge_header, bridging_header, analysis_service, keyboard_key, study_pager, analysis_prompt, app_info, app_entitlements, app_assets, keyboard_info, keyboard_entitlements, products], sourceTree="<group>")

def configs(name, extra):
    ids = []
    for mode in ("Debug", "Release"):
        values = dict(SWIFT_VERSION="5.0", IPHONEOS_DEPLOYMENT_TARGET="15.0", SDKROOT="iphoneos",
                      SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG" if mode == "Debug" else "",
                      CLANG_ENABLE_MODULES="YES", SWIFT_OPTIMIZATION_LEVEL="-Onone" if mode == "Debug" else "-O",
                      DEBUG_INFORMATION_FORMAT="dwarf" if mode == "Debug" else "dwarf-with-dsym")
        values.update(extra)
        if name == "app": values["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] += " EASYTALK_MAIN_APP"
        target_name = {"app": "EasyTalk", "keyboard": "EasyTalkKeyboard"}.get(name)
        values.update(saved_signing.get((target_name, mode), {}))
        ids.append(obj(name + mode, "XCBuildConfiguration", buildSettings=values, name=mode))
    return obj(name + "configs", "XCConfigurationList", buildConfigurations=ids, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

def phases(name, sources):
    builds = [obj(name + source, "PBXBuildFile", fileRef=source) for source in sources]
    return [obj(name + "sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0),
            obj(name + "frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0),
            obj(name + "resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)]

common = dict(CODE_SIGN_STYLE="Automatic", TARGETED_DEVICE_FAMILY="1", CURRENT_PROJECT_VERSION="26",
              CLANG_ENABLE_OBJC_ARC="YES",
              SWIFT_OBJC_BRIDGING_HEADER="Shared/EasyTalkBridging.h",
              MARKETING_VERSION="0.5.0", SUPPORTED_PLATFORMS="iphoneos iphonesimulator",
              # One App Group for shared defaults and Keychain; CI may rewrite the prefix.
              APP_GROUP_IDENTIFIER="group.com.easytalk.personal",
              PRODUCT_NAME="$(TARGET_NAME)", GENERATE_INFOPLIST_FILE="NO")
shared_sources = [settings, shared_storage, input_history, context_export, context_prompt, contracts, learning, learning_store, cursor_navigation, typing_rules, word_suggestions, suggestion_bar, keyboard_preferences, study_practice, second_skill, idiom_catalog, study_content, study_action, study_prompt, speech, app_theme, document_bridge, analysis_service, keyboard_key, study_pager, analysis_prompt]
keyboard = obj("keyboard-target", "PBXNativeTarget",
    buildConfigurationList=configs("keyboard", dict(common, INFOPLIST_FILE="Keyboard/Info.plist",
        PRODUCT_BUNDLE_IDENTIFIER="com.easytalk.personal.keyboard", CODE_SIGN_ENTITLEMENTS="Keyboard/EasyTalkKeyboard.entitlements",
        APPLICATION_EXTENSION_API_ONLY="YES", SKIP_INSTALL="YES",
        LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"])),
    buildPhases=phases("keyboard", [keyboard_source] + shared_sources), buildRules=[], dependencies=[],
    name="EasyTalkKeyboard", productName="EasyTalkKeyboard", productReference=keyboard_product,
    productType="com.apple.product-type.app-extension")
proxy = obj("proxy", "PBXContainerItemProxy", containerPortal=uid("project"), proxyType=1, remoteGlobalIDString=keyboard, remoteInfo="EasyTalkKeyboard")
dependency = obj("dependency", "PBXTargetDependency", target=keyboard, targetProxy=proxy)
embed_file = obj("embed-file", "PBXBuildFile", fileRef=keyboard_product, settings=dict(ATTRIBUTES=["RemoveHeadersOnCopy"]))
embed = obj("embed", "PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath="", dstSubfolderSpec=13,
            files=[embed_file], name="Embed App Extensions", runOnlyForDeploymentPostprocessing=0)
# KeyboardViewController is also compiled into the app for the simulator keyboard preview.
app = obj("app-target", "PBXNativeTarget",
    buildConfigurationList=configs("app", dict(common, INFOPLIST_FILE="EasyTalk/Info.plist",
        PRODUCT_BUNDLE_IDENTIFIER="com.easytalk.personal", CODE_SIGN_ENTITLEMENTS="EasyTalk/EasyTalk.entitlements", ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon", LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/Frameworks"])),
    buildPhases=phases("app", [app_source, history_screen, keyboard_source] + shared_sources) + [embed], buildRules=[], dependencies=[dependency],
    name="EasyTalk", productName="EasyTalk", productReference=app_product, productType="com.apple.product-type.application")
project = obj("project", "PBXProject", attributes=dict(LastUpgradeCheck="1600", BuildIndependentTargetsInParallel="YES"),
    buildConfigurationList=configs("project", {}), compatibilityVersion="Xcode 14.0", developmentRegion="en",
    hasScannedForEncodings=0, knownRegions=["en", "ru", "Base"], mainGroup=main, productRefGroup=products,
    projectDirPath="", projectRoot="", targets=[app, keyboard])
objects[uid("appresources")]["files"].append(obj("assets-copy", "PBXBuildFile", fileRef=app_assets))

# Every referenced file must exist: a typo or a deleted file is an error, not a silent drop.
written_below = {"Shared/ContextExportPrompt.swift", "EasyTalk/Info.plist", "Keyboard/Info.plist", "EasyTalk/EasyTalk.entitlements", "Keyboard/EasyTalkKeyboard.entitlements"}
missing = sorted(value["path"] for value in objects.values()
    if value.get("isa") == "PBXFileReference" and value.get("sourceTree") == "<group>"
    and value["path"] not in written_below and not (ROOT / value["path"]).exists())
if missing:
    raise SystemExit("Missing project files: " + ", ".join(missing))

def encode(value, indent=0):
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (indent + 1) + json.dumps(k) + " = " + encode(v, indent + 1) + ";\n" for k, v in value.items()) + "\t" * indent + "}"
    if isinstance(value, list):
        return "(" + ", ".join(encode(v, indent) for v in value) + ("," if value else "") + ")"
    if isinstance(value, int):
        return str(value)
    return json.dumps(value)

project_dir = ROOT / "EasyTalk.xcodeproj"
project_dir.mkdir(exist_ok=True)
(project_dir / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode(dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project)) + "\n", encoding="utf-8", newline="\n")

base = dict(CFBundleDevelopmentRegion="en", CFBundleDisplayName="easytalk", CFBundleExecutable="$(EXECUTABLE_NAME)",
    CFBundleIdentifier="$(PRODUCT_BUNDLE_IDENTIFIER)", CFBundleInfoDictionaryVersion="6.0", CFBundleName="$(PRODUCT_NAME)",
    CFBundleShortVersionString="$(MARKETING_VERSION)", CFBundleVersion="$(CURRENT_PROJECT_VERSION)",
    EasyTalkAppGroup="$(APP_GROUP_IDENTIFIER)")
app_plist = dict(base, CFBundlePackageType="APPL", LSRequiresIPhoneOS=True, UILaunchScreen={},
    UISupportedInterfaceOrientations=["UIInterfaceOrientationPortrait"],
    # Only HTTPS via URLSession: exempt; avoids the TestFlight export-compliance prompt.
    ITSAppUsesNonExemptEncryption=False)
keyboard_plist = dict(base, CFBundlePackageType="XPC!", NSExtension=dict(
    NSExtensionAttributes=dict(IsASCIICapable=True, PrefersRightToLeft=False, PrimaryLanguage="en-US", RequestsOpenAccess=True),
    NSExtensionPointIdentifier="com.apple.keyboard-service",
    NSExtensionPrincipalClass="$(PRODUCT_MODULE_NAME).KeyboardViewController"))
entitlements = {"com.apple.security.application-groups": ["$(APP_GROUP_IDENTIFIER)"]}
for path, data in [("EasyTalk/Info.plist", app_plist), ("Keyboard/Info.plist", keyboard_plist),
                   ("EasyTalk/EasyTalk.entitlements", entitlements), ("Keyboard/EasyTalkKeyboard.entitlements", entitlements)]:
    (ROOT / path).write_bytes(plistlib.dumps(data))

scheme_dir = project_dir / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="EasyTalk.app" BlueprintName="EasyTalk" ReferencedContainer="container:EasyTalk.xcodeproj"/>'
(scheme_dir / "EasyTalk.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''', encoding="utf-8", newline="\n")
print("Generated ios/EasyTalk.xcodeproj")
