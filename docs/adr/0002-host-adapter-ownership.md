# Keep presentation and platform behavior in host adapters

The native core owns host-neutral Syncthing state and actions. Each host adapter
owns its native presentation, settings, package behavior, notifications,
pickers, URLs, paths, and removal flow. Root `Panel.qml` and `Service.qml`
remain the stable Omarchy entry boundary so the plugin retains its native
manifest, bar placement, and hot-update behavior.

A shared view model or generic platform abstraction is rejected for 0.1.8
because only Omarchy is supported and forwarding layers would create a second
owner without adding behavior.
