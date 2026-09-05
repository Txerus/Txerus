from pathlib import Path
import plistlib

plist_path = Path('playtorrio/ios/Runner/Info.plist')
with plist_path.open('rb') as f:
    plist = plistlib.load(f)

manifest = plist.setdefault('UIApplicationSceneManifest', {})
manifest['UIApplicationSupportsMultipleScenes'] = True
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
configs['UIWindowSceneSessionRoleCarPlay'] = [{
    'UISceneConfigurationName': 'PlayTorrio CarPlay Window',
    'UISceneDelegateClassName': delegate,
}]

plist['NSUserActivityTypes'] = list(dict.fromkeys(plist.get('NSUserActivityTypes', []) + ['INPlayMediaIntent']))
plist['NSBonjourServices'] = list(dict.fromkeys(plist.get('NSBonjourServices', []) + ['_airplay._tcp', '_raop._tcp']))

with plist_path.open('wb') as f:
    plistlib.dump(plist, f, fmt=plistlib.FMT_XML, sort_keys=False)

print('CarPlay V5 diagnostic scene roles applied.')
