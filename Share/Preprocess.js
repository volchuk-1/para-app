// Runs inside the page Safari has open when you tap «Поділитися → DaVincit».
// Shops behind bot protection refuse our server, but the page is already here, so we hand over
// only what describes the product: <title>, meta tags, JSON-LD and microdata — never cookies or forms.
var DaVincitPreprocess = function () {};

DaVincitPreprocess.prototype = {
  run: function (args) {
    var out = [];
    var esc = function (s) { return String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;'); };
    try {
      out.push('<title>' + esc(document.title || '') + '</title>');
      document.querySelectorAll('meta[property], meta[name], meta[itemprop]').forEach(function (m) {
        var key = m.getAttribute('property') ? 'property' : (m.getAttribute('name') ? 'name' : 'itemprop');
        out.push('<meta ' + key + '="' + esc(m.getAttribute(key)) + '" content="' + esc(m.getAttribute('content') || '') + '">');
      });
      document.querySelectorAll('script[type="application/ld+json"]').forEach(function (s) {
        out.push('<script type="application/ld+json">' + (s.textContent || '').replace(/<\/script/gi, '<\\/script') + '</script>');
      });
      document.querySelectorAll('[itemprop]:not(meta)').forEach(function (el) {
        var v = el.getAttribute('content') || el.getAttribute('src') || el.getAttribute('href') || (el.textContent || '').trim();
        if (v && v.length < 500) out.push('<meta itemprop="' + esc(el.getAttribute('itemprop')) + '" content="' + esc(v) + '">');
      });
    } catch (e) {}
    var page = out.join('\n');
    if (page.length > 380000) page = page.slice(0, 380000);
    args.completionFunction({ url: document.URL, page: page });
  },
  finalize: function () {}
};

var ExtensionPreprocessingJS = new DaVincitPreprocess();
