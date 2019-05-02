require "lita"

Lita.load_locales Dir[File.expand_path(
  File.join("..", "..", "locales", "*.yml"), __FILE__
)]

require "teamcityhelper/misc"
require "lita/handlers/teamcity"

Lita::Handlers::Teamcity.template_root File.expand_path(
  File.join("..", "..", "templates"),
 __FILE__
)
