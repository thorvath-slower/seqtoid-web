# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# CZID-313: the webpack build (webpack.config.common.js url-loader rules) emits vendored font
# assets — e.g. the semantic-ui-css icon font — to app/assets/fonts, and the generated CSS
# references them at /assets/<name>. app/assets/fonts is not a default sprockets load path, so
# register it here (and link the fonts in app/assets/config/manifest.js). Without this, under
# unknown_asset_fallback=false sprockets raises (HTTP 500) and the icon glyphs render as □.
Rails.application.config.assets.paths << Rails.root.join("app", "assets", "fonts")

# Precompile additional assets.
# application.js, application.css, and all non-JS/CSS in the app/assets
# folder are already added.
# Rails.application.config.assets.precompile += %w( admin.js admin.css )
