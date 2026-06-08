// assets/javascripts/lib/discourse-markdown/preview-bbcode.js
//
// Markdown-it BBCode rule for [preview]...[/preview].
//
// This follows the pattern described in the rich editor docs and the
// Snapblocks example: emit bbcode_open / text / bbcode_close tokens,
// so the rich text editor can recognize and round-trip the tag cleanly.
//
// It does NOT render the preview; your theme component still decorates
// cooked HTML. This only shapes the token stream.

export function setup(helper) {
  // Discourse passes a `helper` which exposes markdown-it as markdownIt or md
  const md = helper.markdownIt || helper.md;

  if (!md || !md.bbcode || !md.inline?.bbcode) {
    return;
  }

  // Inline BBCode rule for [preview]CONTENT[/preview]
  md.inline.bbcode.ruler.push("preview", {
    tag: "preview",

    // Replace function is called with the raw CONTENT between tags
    replace(state, tagInfo, content) {
      // Opening token
      let token = state.push("bbcode_open", "span", 1);
      // Mark it so the RTE extension can detect it
      token.attrs = [["class", "preview-bbcode"]];

      // Inner text token – this will be further parsed into inline nodes
      token = state.push("text", "", 0);
      token.content = content;

      // Closing token
      token = state.push("bbcode_close", "span", -1);
      token.attrs = [["class", "preview-bbcode"]];
    },
  });
}