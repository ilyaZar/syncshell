# Keep Omarchy settings outside the native core

Omarchy remains the sole owner of its existing four-field settings file,
including parsing, watching, safe writes, editor integration, defaults, and
errors. The native core receives only validated, nonsecret operational values
that affect its session, and never receives, parses, watches, or writes the
settings path or style preferences.

This avoids turning one host's physical file into a false cross-shell contract.
Future hosts will own their own presentation settings while sharing the native
core protocol.
