.pragma library

var DefaultIconStyle = "branded"
var DefaultWebUiTheme = "omarchy"
var DefaultServiceState = "enabled"
var DefaultProbeIntervalSeconds = 15
var MinimumProbeIntervalSeconds = 1
var MaximumProbeIntervalSeconds = 3600
var SupportedVersion = 1

function stripComment(line) {
  var quote = ""
  for (var i = 0; i < line.length; i++) {
    var character = line.charAt(i)
    if ((character === "\"" || character === "'") && !quote) {
      quote = character
    } else if (character === quote) {
      quote = ""
    } else if (character === "#" && !quote) {
      return line.slice(0, i)
    }
  }
  return line
}

function parseValue(raw) {
  var value = String(raw || "").trim()
  var match = value.match(/^(["'])([^"']*)\1$/)
  return match ? match[2] : null
}

function parseVersion(raw) {
  var value = String(raw || "").trim()
  return /^(0|[1-9][0-9]*)$/.test(value) ? Number(value) : null
}

function parseInteger(raw) {
  var value = String(raw || "").trim()
  return /^(0|[1-9][0-9]*)$/.test(value) ? Number(value) : null
}

function parse(raw) {
  var values = ({})
  var lines = String(raw || "").split("\n")
  var section = ""
  var version = null
  var styleSectionSeen = false
  var serviceSectionSeen = false
  var rootStyleSetting = false

  for (var i = 0; i < lines.length; i++) {
    var line = stripComment(lines[i]).trim()
    if (!line) continue
    var header = line.match(/^\[([A-Za-z_][A-Za-z0-9_-]*)\]$/)
    if (header) {
      section = header[1]
      if (section !== "style" && section !== "service") {
        return { error: "Unknown settings section " + section
          + " on line " + (i + 1) }
      }
      if ((section === "style" && styleSectionSeen)
          || (section === "service" && serviceSectionSeen)) {
        return { error: "Duplicate settings section " + section
          + " on line " + (i + 1) }
      }
      if (section === "style") styleSectionSeen = true
      else serviceSectionSeen = true
      continue
    }
    var assignment = line.match(/^([A-Za-z_][A-Za-z0-9_-]*)\s*=\s*(.+)$/)
    if (!assignment) {
      return { error: "Invalid settings syntax on line " + (i + 1) }
    }
    var key = assignment[1]
    if (key === "version" && !section) {
      if (version !== null) {
        return { error: "Duplicate setting version on line " + (i + 1) }
      }
      version = parseVersion(assignment[2])
      if (version === null) {
        return { error: "version must be an integer" }
      }
      continue
    }
    var styleSetting = key === "icon_style" || key === "web_ui_theme"
    var serviceSetting = key === "service_state"
      || key === "probe_interval_seconds"
    if ((section === "service" && !serviceSetting)
        || (section !== "service" && !styleSetting)) {
      return { error: "Unknown setting " + (section ? section + "." : "")
        + key + " on line " + (i + 1) }
    }
    if (!section && styleSetting) rootStyleSetting = true
    if (values[key] !== undefined) {
      return { error: "Duplicate setting " + key + " on line " + (i + 1) }
    }
    if (key === "probe_interval_seconds") {
      var interval = parseInteger(assignment[2])
      if (interval === null || interval < MinimumProbeIntervalSeconds
          || interval > MaximumProbeIntervalSeconds) {
        return { error: "probe_interval_seconds must be an integer between "
          + MinimumProbeIntervalSeconds + " and " + MaximumProbeIntervalSeconds }
      }
      values[key] = interval
    } else {
      var value = parseValue(assignment[2])
      if (value === null) {
        return { error: key + " must use a quoted value" }
      }
      values[key] = value
    }
  }

  if (version !== null || styleSectionSeen) {
    if (version === null) return { error: "Missing setting version" }
    if (version !== SupportedVersion) {
      return { error: "Unsupported settings version " + version }
    }
    if (!styleSectionSeen) return { error: "Missing settings section style" }
    if (rootStyleSetting) {
      return { error: "Style settings must be inside [style]" }
    }
  }

  if (values.icon_style === undefined) {
    return { error: "Missing setting icon_style" }
  }
  if (["branded", "themed"].indexOf(values.icon_style) < 0) {
    return { error: "icon_style must be branded or themed" }
  }
  if (values.web_ui_theme === undefined) {
    return { error: "Missing setting web_ui_theme" }
  }
  if (["default", "omarchy"].indexOf(values.web_ui_theme) < 0) {
    return { error: "web_ui_theme must be default or omarchy" }
  }
  if (values.service_state === undefined) {
    values.service_state = DefaultServiceState
  }
  if (["enabled", "disabled"].indexOf(values.service_state) < 0) {
    return { error: "service_state must be enabled or disabled" }
  }
  if (values.probe_interval_seconds === undefined) {
    values.probe_interval_seconds = DefaultProbeIntervalSeconds
  }

  return {
    error: "",
    iconStyle: values.icon_style,
    webUiTheme: values.web_ui_theme,
    serviceState: values.service_state,
    probeIntervalSeconds: values.probe_interval_seconds
  }
}

function defaults(legacyThemedIcon) {
  return {
    iconStyle: legacyThemedIcon === true ? "themed" : DefaultIconStyle,
    webUiTheme: DefaultWebUiTheme,
    serviceState: DefaultServiceState,
    probeIntervalSeconds: DefaultProbeIntervalSeconds
  }
}
