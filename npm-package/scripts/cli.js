#!/usr/bin/env node

const child_process = require("child_process");

const arguments = process.argv.slice(2);

child_process.spawnSync("node_modules/gotyno/bin/gotyno", arguments, { stdio: "inherit" });
