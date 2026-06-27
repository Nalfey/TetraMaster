local Settings = {
  DEFAULT_CHARACTER = "random",
}

function Settings.normalize_name(name)
  return (name or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
end

function Settings.section_key(player_name)
  local key = Settings.normalize_name(player_name)
  key = key:gsub("[^%w_]", "")
  return key
end

function Settings.addon_path(addon_root)
  return (addon_root or ""):gsub("\\", "/"):gsub("/+$", "")
end

function Settings.data_dir(addon_root)
  return Settings.addon_path(addon_root) .. "/data"
end

function Settings.settings_path(addon_root)
  return Settings.data_dir(addon_root) .. "/settings.xml"
end

function Settings.default_xml()
  return table.concat({
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<settings>",
    "  <global>",
    "    <character>random</character>",
    "  </global>",
    "</settings>",
    "",
  }, "\n")
end

function Settings.ensure_data_dir(addon_root)
  local dir = Settings.data_dir(addon_root):gsub("/", "\\")
  os.execute('if not exist "' .. dir .. '" mkdir "' .. dir .. '"')
end

function Settings.trim(value)
  if not value then
    return nil
  end

  value = value:match("^%s*(.-)%s*$")
  if not value or value == "" then
    return nil
  end

  return value
end

function Settings.read_character_from_section(section_content)
  if not section_content then
    return nil
  end

  return Settings.trim(section_content:match("<character%s*>(.-)</character>"))
end

function Settings.extract_section(content, key)
  if not content or not key or key == "" then
    return nil
  end

  local pattern = "<" .. key .. ">(.-)</" .. key .. ">"
  return content:match(pattern)
end

function Settings.global_character(content)
  local global_section = Settings.extract_section(content, "global")
  return Settings.read_character_from_section(global_section) or Settings.DEFAULT_CHARACTER
end

function Settings.section_exists(content, key)
  if not content or not key or key == "" then
    return false
  end

  return content:match("<" .. key .. ">") ~= nil
end

function Settings.build_player_section(key, character)
  return table.concat({
    "  <" .. key .. ">",
    "    <character>" .. character .. "</character>",
    "  </" .. key .. ">",
    "",
  }, "\n")
end

function Settings.write_settings(path, content)
  local file = io.open(path, "w")
  if not file then
    return false
  end

  file:write(content)
  file:close()
  return true
end

function Settings.ensure_player_section(content, player_name)
  local key = Settings.section_key(player_name)
  if not key or key == "" or key == "global" then
    return content, false
  end

  if Settings.section_exists(content, key) then
    return content, false
  end

  local character = Settings.global_character(content)
  local block = Settings.build_player_section(key, character)
  local updated

  if content:match("</settings>") then
    updated = content:gsub("</settings>", block .. "</settings>", 1)
  else
    updated = Settings.default_xml():gsub("</settings>", block .. "</settings>", 1)
  end

  return updated, true
end

function Settings.read_character_preference(content, player_name)
  if not content or content == "" then
    return Settings.DEFAULT_CHARACTER
  end

  local player_key = Settings.section_key(player_name)
  if player_key and player_key ~= "" then
    local player_section = Settings.extract_section(content, player_key)
    local player_value = Settings.read_character_from_section(player_section)
    if player_value then
      return player_value
    end
  end

  local global_section = Settings.extract_section(content, "global")
  local global_value = Settings.read_character_from_section(global_section)
  if global_value then
    return global_value
  end

  if not content:match("<global>") then
    local legacy_value = Settings.trim(content:match("<character%s*>(.-)</character>"))
    if legacy_value then
      return legacy_value
    end
  end

  return Settings.DEFAULT_CHARACTER
end

function Settings.load(addon_root, player_name)
  if not addon_root or addon_root == "" then
    return { character = Settings.DEFAULT_CHARACTER }
  end

  Settings.ensure_data_dir(addon_root)

  local path = Settings.settings_path(addon_root)
  local file = io.open(path, "r")
  local content

  if not file then
    content = Settings.default_xml()
  else
    content = file:read("*a") or ""
    file:close()
  end

  local updated, changed = Settings.ensure_player_section(content, player_name)
  if changed or not file then
    Settings.write_settings(path, updated)
    content = updated
  end

  return {
    character = Settings.read_character_preference(content, player_name),
  }
end

return Settings
