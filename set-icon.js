const path = require("path");
const { rcedit } = require("rcedit");

const executable = path.resolve(__dirname, "dist", "BlackScreenGuard.exe");
const icon = path.resolve(__dirname, "assets", "BlackScreenGuard.ico");

rcedit(executable, {
  icon,
  "version-string": {
    ProductName: "BlackScreen Guard",
    FileDescription: "BlackScreen Guard for Windows 11",
    OriginalFilename: "BlackScreenGuard.exe",
  },
  "file-version": "1.0.1.0",
  "product-version": "1.0.1.0",
}).catch((error) => {
  console.error(error);
  process.exit(1);
});
