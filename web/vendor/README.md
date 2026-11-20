# PDF template browser assets

These are self-hosted upstream distributions; do not edit the library bundles.

| Asset | Version | Upstream |
| --- | --- | --- |
| `pdf-lib.min.js` | pdf-lib 1.17.1 | https://www.npmjs.com/package/pdf-lib/v/1.17.1 |
| `fontkit.umd.min.js` | @pdf-lib/fontkit 1.1.1 | https://www.npmjs.com/package/@pdf-lib/fontkit/v/1.1.1 |
| `NotoSans-Regular.ttf` | Noto Sans Regular | https://github.com/notofonts/noto-fonts/blob/main/hinted/ttf/NotoSans/NotoSans-Regular.ttf |

MIT notices for pdf-lib and fontkit and the SIL Open Font License for Noto Sans
are included alongside the files. The fontkit fork retains the upstream
foliojs/fontkit MIT license.

To update the JavaScript assets, obtain the pinned npm packages and copy their
matching `dist/` files here. Keep the browser assets and their notices together.
Run `node --test tools/pdf_template_test.mjs` after changes; this test loads these
exact assets, not node_modules copies.
