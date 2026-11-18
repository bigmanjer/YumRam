# Optional Cleanup Research

YUMRAM separates cooperative user-app cleanup from Windows service cleanup. Microsoft documents per-app controls for background activity, so YUMRAM treats background desktop apps as explicit user choices rather than assuming an app is “useless.”

Recommended catalog candidates are: OneDrive, Teams, ms-teams, Skype, PhoneExperienceHost, YourPhone, Slack, CCXProcess, AdobeCollabSync, EADesktop, Battle.net, and EpicGamesLauncher. Each can be useful and may affect sync/session behavior, so they are presented as recommendations and require explicit user selection.

Windows services remain more restrictive. YUMRAM only considers explicitly user-approved services that can be stopped, have no running dependents, and use Manual startup mode. It never changes service startup type. Microsoft warns that stopping a service can also stop dependent services.


## 4.5.9 Scanner model

YUMRAM now inventories processes, services, and AppX packages and classifies candidates using evidence rather than a fixed bloatware list. Foreground and active-game processes are protected; unknown software is review-only. Optional app closure remains cooperative and user-approved, while optional services require explicit approval, dependency checks, CanStop, and Manual start mode.

Microsoft notes that Windows already gives foreground apps more memory/execution time and provides controls for supported background activity, so YUMRAM treats background classification as evidence-based rather than assuming all background activity is waste.
