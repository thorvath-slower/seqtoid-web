//= link_tree ../images
//= link_directory ../javascripts .js
//= link_directory ../stylesheets .css
//= link_directory ../webassembly .js
//= link_directory ../webassembly .wasm
//= link_directory ../webassembly .json
//= link application.css
// CZID-313: register webpack-emitted vendored fonts (e.g. semantic-ui-css icons) so sprockets
// will serve /assets/<font> under unknown_asset_fallback=false. See config/initializers/assets.rb.
//= link_tree ../fonts
