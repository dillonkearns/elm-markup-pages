#!/usr/bin/env node

const build = require("./build.js");
const dev = require("./dev-server.js");
const generate = require("./codegen-template-module.js");
const init = require("./init.js");
const codegen = require("./codegen.js");
const fs = require("fs");
const path = require("path");

const commander = require("commander");

const packageVersion = require("../../package.json").version;

async function main() {
  const program = new commander.Command();

  program.version(packageVersion);

  program
    .command("build")
    .option("--debug", "Skip terser and run elm make with --debug")
    .option(
      "--base <basePath>",
      "build site to be served under a base path",
      "/"
    )
    .option(
      "--keep-cache",
      "Preserve the HTTP and JS Port cache instead of deleting it on server start"
    )
    .description("run a full site build")
    .action(async (options) => {
      if (!options.keepCache) {
        clearHttpAndPortCache();
      }
      options.base = normalizeUrl(options.base);
      await build.run(options);
    });

  program
    .command("dev")
    .description("start a dev server")
    .option("--port <number>", "serve site at localhost:<port>", "1234")
    .option(
      "--keep-cache",
      "Preserve the HTTP and JS Port cache instead of deleting it on server start"
    )
    .option("--base <basePath>", "serve site under a base path", "/")
    .action(async (options) => {
      if (!options.keepCache) {
        clearHttpAndPortCache();
      }
      options.base = normalizeUrl(options.base);
      await dev.start(options);
    });

  program
    .command("add <moduleName>")
    .description("create a new Page module")
    .action(async (moduleName) => {
      await generate.run({ moduleName });
    });

  program
    .command("init <projectName>")
    .description("scaffold a new elm-pages project boilerplate")
    .action(async (projectName) => {
      await init.run(projectName);
    });

  program
    .command("docs")
    .description("open the docs for locally generated modules")
    .option("--port <number>", "serve site at localhost:<port>", "8000")
    .action(async (options) => {
      await codegen.generate("/");
      const DocServer = require("elm-doc-preview");
      const server = new DocServer({
        port: options.port,
        browser: true,
        dir: "./elm-stuff/elm-pages/",
      });

      server.listen();
    });

  program.parse(process.argv);
}

function clearHttpAndPortCache() {
  const directory = ".elm-pages/http-response-cache";
  if (fs.existsSync(directory)) {
    fs.readdir(directory, (err, files) => {
      if (err) {
        throw err;
      }

      for (const file of files) {
        fs.unlink(path.join(directory, file), (err) => {
          if (err) {
            throw err;
          }
        });
      }
    });
  }
}

/**
 * @param {string} pagePath
 */
function normalizeUrl(pagePath) {
  if (!pagePath.startsWith("/")) {
    pagePath = "/" + pagePath;
  }
  const isRoot = pagePath === "/";
  if (pagePath.endsWith("/") && !isRoot) {
    pagePath = pagePath.slice(0, pagePath.length);
  }
  return pagePath;
}

main();
