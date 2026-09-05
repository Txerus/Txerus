from pathlib import Path
import plistlib

plist_path = Path('playtorrio/ios/Runner/Info.plist')
with plist_path.open('rb') as f:
    plist = plistlib.load(f)

manifest = plist.setdefault('UIApplicationSceneManifest', {})
manifest['UIApplicationSupportsMultipleScenes'] = False
manifest['CPSupportsDashboardNavigationScene'] = True
configs = manifest.setdefault('UISceneConfigurations', {})

delegate = '$(PRODUCT_MODULE_NAME).PlayTorrioCarPlaySceneDelegate'

configs['CPTemplateApplicationSceneSessionRoleApplication'] = [{
    'UISceneConfigurationName': 'PlayTorrio CarPlay',
    'UISceneClassName': 'CPTemplateApplicationScene',
    'UISceneDelegateClassName': delegate,
}]

configs['CPTemplateApplicationDashboardSceneSessionRoleApplication'] = [{
    'UISceneConfigurationName': 'PlayTorrio CarPlay Dashboard',
    'UISceneClassName': 'CPTemplateApplicationDashboardScene',
    'UISceneDelegateClassName': delegate,
}]

# Legacy role still announced by some older head units. This does not draw
# arbitrary video into the CarPlay window; it only gives the system another
# standards-based route to instantiate the same template delegate.
configs['UIWindowSceneSessionRoleCarPlay'] = [{
    'UISceneDelegateClassName': delegate,
}]

with plist_path.open('wb') as f:
    plistlib.dump(plist, f, fmt=plistlib.FMT_XML, sort_keys=False)

# Add the CPWindow delegate overload used by legacy CarPlay scene delivery.
app_delegate = Path('playtorrio/ios/Runner/AppDelegate.swift')
s = app_delegate.read_text()
anchor = '''  func templateApplicationScene(\n    _ templateApplicationScene: CPTemplateApplicationScene,\n    didDisconnectInterfaceController interfaceController: CPInterfaceController\n  ) {\n'''
method = '''  func templateApplicationScene(\n    _ templateApplicationScene: CPTemplateApplicationScene,\n    didConnect interfaceController: CPInterfaceController,\n    to window: CPWindow\n  ) {\n    // Some legacy CarPlay systems deliver the same template scene together\n    // with a CPWindow. Reuse the normal system-template setup.\n    self.templateApplicationScene(templateApplicationScene, didConnect: interfaceController)\n    window.backgroundColor = .black\n    window.makeKeyAndVisible()\n  }\n\n'''
if method not in s:
    if anchor not in s:
        raise SystemExit('CarPlay delegate anchor not found')
    s = s.replace(anchor, method + anchor, 1)
    app_delegate.write_text(s)

print('Applied standards-based legacy CarPlay scene compatibility wiring.')
