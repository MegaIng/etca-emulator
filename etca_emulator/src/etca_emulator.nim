# This is just an example to get you started. A typical hybrid package
# uses this file as the main entry point of the application.

import etca_emulatorpkg/memory_maps
import etca_emulatorpkg/CPU
import jsony
import parseutils
import print

proc parseHook(s: string, i: var int, v: var uint64) =
  var str: string
  eatSpace(s, i)
  if s[i] == '"':
    parseHook(s, i, str)
    discard parseHex[uint64](str, v)
  else:
    var
      v2: uint64 = 0
      startI = i
    while i < s.len and s[i] in {'0'..'9'}:
      v2 = v2 * 10 + (s[i].ord - '0'.ord).uint64
      inc i
    if startI == i:
      raise newException(JsonError, "Number expected. At offset: " & $i)
    v = type(v)(v2)

when isMainModule:
  let memory_desc = open("etca_kernel_memory.json").readAll().fromJson(MemoryMapDescription)
  let memory = memory_desc.construct()
  var cpu = build_cpu(memory)
  #cpu.debug = {log_instructions}#, log_memory_access, log_flags, log_registers}
  cpu.run()
