var process = require("process");
var fs = require("fs");

const maybeExtension = process.platform === "win32" ? ".exe" : "";
const BIN_PATH = `./bin/gotyno${maybeExtension}`;

fs.symlinkSync(`${process.platform}/gotyno${maybeExtension}`, BIN_PATH);
fs.chmodSync(BIN_PATH, 0o755);
