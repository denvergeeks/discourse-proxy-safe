// assets/javascripts/lib/rich-text-editor-extension.js
//
// Rich text editor extension for [preview]...[/preview].
//
// This consumes the bbcode_open/text/bbcode_close tokens emitted by
// preview-bbcode.js and turns them into a ProseMirror node called `preview`.
// When serializing back to Markdown, it writes [preview]...[/preview] exactly,
// so the new editor no longer needs to escape the brackets.

const previewExtension = {
  // Define a node type used by the rich editor
  preview: {
    group: "inline",
    inline: true,
    content: "inline*",

    // Map existing preview wraps in HTML (from your theme) into this node
    parseDOM: [
      {
        tag: "span.rich-preview-wrap",
      },
    ],

    // How to render the node into the rich editor DOM
    toDOM(node) {
      return ["span", { class: "rich-preview-wrap" }, 0];
    },
  },

  // Parse markdown-it's token stream into preview nodes
  parse: {
    // Called for bbcode_open tokens
    bbcode_open(state, token) {
      // Match tokens produced by preview-bbcode.js
      if (token.attrGet("class") === "preview-bbcode") {
        state.openNode(state.schema.nodes.preview, {});
        return true;
      }
      return false;
    },

    // Called for bbcode_close tokens
    bbcode_close(state, token) {
      if (token.attrGet("class") === "preview-bbcode") {
        state.closeNode();
        return true;
      }
      return false;
    },
  },

  // Serialize preview nodes back to Markdown/BBCode
  serializeNode: {
    preview(state, node) {
      // Write original wrapper, then render inline content inside
      state.write("[preview]");
      state.renderContent(node);
      state.write("[/preview]");
    },
  },
};

export default previewExtension;