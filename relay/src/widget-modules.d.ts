// The web widget's files, bundled by the wrangler.jsonc `rules`: text as strings, fonts as bytes.
declare module "*.html" {
  const text: string;
  export default text;
}
declare module "*.css" {
  const text: string;
  export default text;
}
declare module "*/widget/standby.js" {
  const text: string;
  export default text;
}
declare module "*.ttf" {
  const bytes: ArrayBuffer;
  export default bytes;
}
