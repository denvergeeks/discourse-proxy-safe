// assets/javascripts/initializers/preview-rich-editor.js
//
// Registers the [preview] rich text editor extension using the plugin API.

import { apiInitializer } from "discourse/lib/api";
import previewExtension from "../lib/rich-text-editor-extension";

export default apiInitializer("0.11.0", (api) => {
  // This hook is documented in the rich editor extension guides and is
  // used for Snapblocks and other markdown integrations.[web:121][web:144]
  api.registerRichEditorExtension(previewExtension);
});