const parseUrl = require("url").parse;

// this middleware is only active when (config.base !== '/')

// `base` is assumed NOT to end with a trailing slash.
module.exports = function baseMiddleware(base) {
  // Keep the named function. The name is visible in debug logs via `DEBUG=connect:dispatcher ...`
  return function viteBaseMiddleware(req, res, next) {
    const url = req.url;
    const parsed = parseUrl(url);
    const path = parsed.pathname || "/";

    if (path.startsWith(base)) {
      // rewrite url to remove base. this ensures that other middleware does
      // not need to consider base being prepended or not
      const regexp = new RegExp(base + "/?");
      req.url = url.replace(regexp, "/");
      return next();
    }

    if (path === "/" || new RegExp("/index.html/?").test(path)) {
      // redirect root visit to based url
      res.writeHead(302, {
        Location: base + "/",
      });
      res.end();
      return;
    } else if (req.headers.accept && req.headers.accept.includes("text/html")) {
      // non-based page visit
      res.statusCode = 404;
      res.end(
        `The server is configured with a public base URL of ${base + "/"} - ` +
        `did you mean to visit ${base + "/"}${url.slice(1)} instead?`
      );
      return;
    }

    next();
  };
};
