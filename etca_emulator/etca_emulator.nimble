# Package

version       = "0.1.0"
author        = "MegaIng"
description   = "An Emulator for ETCa: https://github.com/ETC-A/etca-spec"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["etca_emulator"]


# Dependencies

requires "nim >= 1.6.6"
requires "patty"
requires "jsony"
requires "print"