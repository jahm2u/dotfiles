module.exports = {
  inputDir: './svgs',
  outputDir: './font',
  fontTypes: ['ttf', 'woff', 'woff2'],
  assetTypes: ['json'],
  name: 'SimpleIcons',
  prefix: 'si',
  codepoints: {}, // Auto-generate codepoints
  fontHeight: 1000,
  descent: 150,
  normalize: true,
  round: 10e12,
  selector: '.si',
  tag: 'i',
  templates: {},
  pathOptions: {}
};
