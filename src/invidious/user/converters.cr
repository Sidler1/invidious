# Themes the stylesheet defines. The value ends up in the `class` attribute
# of `<body>` (template.ecr), so anything else must be rejected here.
THEMES = {"dark", "light"}

def convert_theme(theme : String?) : String?
  case theme
  when "true"  then "dark"
  when "false" then "light"
  when nil, "" then nil
  else
    THEMES.includes?(theme) ? theme : nil
  end
end

# Returns the locale only if a translation file for it exists. The value is
# reflected into `<html lang="...">`, so unknown values are dropped.
def sanitize_locale(locale : String?) : String?
  return nil if locale.nil?
  I18n::LOCALES.has_key?(locale) ? locale : nil
end
