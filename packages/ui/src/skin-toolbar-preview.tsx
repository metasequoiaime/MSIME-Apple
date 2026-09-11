import toolbarMarkup from "./upstream/skin-toolbar-preview.html?raw";

/** Build-time, script-free upstream sample; never accepts runtime HTML. */
export function SkinToolbarPreview() {
  return <div className="ftb-preview-host" aria-hidden="true" dangerouslySetInnerHTML={{ __html: toolbarMarkup }} />;
}
