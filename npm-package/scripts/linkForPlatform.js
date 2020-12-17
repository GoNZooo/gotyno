var process = require("process");
var fs = require("fs");

if (process.platform !== "darwin") {
  const maybeExtension = process.platform === "win32" ? ".exe" : "";
  const BIN_PATH = `./bin/gotyno${maybeExtension}`;

  fs.symlinkSync(`${process.platform}/gotyno${maybeExtension}`, BIN_PATH);
  fs.chmodSync(BIN_PATH, 0o755);
} else {
  console.warn("Unfortunately MacOS users currently need to compile `gotyno` themselves.");
  console.warn(
    "In the future cross-compilation from Linux/Windows for MacOS will be solved, but currently I'm unable to compile for MacOS."
  );
  console.warn(
    "The repository can be found at https://github.com/GoNZooo/gotyno and the Zig compiler can be found at https://ziglang.org/download/"
  );
  console.warn("I may look for someone who can help me with this.");
}
