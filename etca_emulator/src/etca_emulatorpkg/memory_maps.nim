import instructions
import std/options

type
    MemoryMap* = ref object of RootObj

    SectionMapper* = ref object of MemoryMap
        ranges*: seq[Slice[uint64]]
        mappers*: seq[MemoryMap]
    
    RAMMapper* = ref object of MemoryMap
        readonly*: bool
        data*: seq[uint8]
    
    MMIOFileStream* = ref object of MemoryMap
        read: bool
        write: bool
        file: File
    
    MMIOConstant* = ref object of MemoryMap
        value: uint64
    

method get*(mem: MemoryMap, address: uint64, width: BitWidth): uint64 {.base.} =
    quit "to override!"

method set*(mem: MemoryMap, address: uint64, width: BitWidth,
        value: uint64) {.base.} =
    quit "to override!"



method get*(mem: SectionMapper, address: uint64, width: BitWidth): uint64 =
    for i, r in mem.ranges:
        if address in r:
            return mem.mappers[i].get(address - r.a, width)


method set*(mem: SectionMapper, address: uint64, width: BitWidth, value: uint64) =
    for i, r in mem.ranges:
        if address in r:
            mem.mappers[i].set(address - r.a, width, value)



method get*(mem: RAMMapper, address: uint64, width: BitWidth): uint64 =
    for i in 0 ..< byte_count(width):
        if address.int + i <= mem.data.high:
            result = result or (mem.data[address + i.uint8].uint64 shl (i*8))



method set*(mem: RAMMapper, address: uint64, width: BitWidth, value: uint64) =
    if mem.readonly:
        return
    for i in 0 ..< byte_count(width):
        if address.int <= mem.data.high:
            mem.data[address + i.uint8] = ((value shr (i*8)) and 0xFF).uint8


method get*(mem: MMIOFileStream, address: uint64, width: BitWidth): uint64 =
    for i in 0 ..< byte_count(width):
        if not mem.file.endOfFile:
            result = result or (mem.file.readChar.uint64 shl (i*8))

method set*(mem: MMIOFileStream, address: uint64, width: BitWidth, value: uint64) =
    if mem.write:
        for i in 0 ..< byte_count(width):
            mem.file.write ((value shr (i*8)) and 0xFF).char


method get*(mem: MMIOConstant, address: uint64, width: BitWidth): uint64 =
    return mem.value

method set*(mem: MMIOConstant, address: uint64, width: BitWidth, value: uint64) =
    discard

proc mem_ram_from_file*(file: File, readonly: bool = false): MemoryMap =
    var rammap = new RAMMapper
    rammap.readonly = readonly
    rammap.data = cast[seq[uint8]](file.readAll())
    return rammap

type
    MemoryMapKind* {.pure.} = enum
        sections
        empty_ram

        ram_from_file
        rom_from_file

        stream_stdout
        stream_stdin

        inputstream_file
        outputstream_file

        constant
    
    MapperWithRange = object
        first_addr: uint64
        last_addr: uint64
        mapper: ref MemoryMapDescription

    MemoryMapDescription* = object
        size*: Option[uint64]  # can be infered from a parent if not given
        case kind*: MemoryMapKind
        of sections:
            sections*: seq[MapperWithRange]
        of empty_ram:
            discard
        of ram_from_file, rom_from_file, inputstream_file, outputstream_file:
            path*: string
        of stream_stdout, stream_stdin:
            discard
        of constant:
            value*: uint64

proc construct*(desc: MemoryMapDescription, size: Option[uint64] = none[uint64]()): MemoryMap =
    let given_size = if desc.size.isNone: size else: desc.size
    case desc.kind:
        of sections:
            var mappers: seq[MemoryMap]
            var ranges: seq[Slice[uint64]]
            for child in desc.sections:
                ranges.add (child.first_addr ..  child.last_addr)
                mappers.add child.mapper[].construct(some(child.last_addr - child.first_addr + 1))
            result = SectionMapper(ranges: ranges, mappers: mappers)
        of empty_ram:
            if given_size.isNone:
                raise newException(ValueError, "Can't figure out size of ram memory section")
            result = RAMMapper(readonly: false, data: newSeqUninitialized[uint8](given_size.get))
        of ram_from_file, rom_from_file:
            let file = open(desc.path)
            var data = cast[seq[uint8]](file.readAll())
            if given_size.isSome:
                data.setLen given_size.get
            result = RAMMapper(readonly: desc.kind==rom_from_file, data: data)
        of inputstream_file:
            let file = open(desc.path)
            result = MMIOFileStream(file: file, read: true)
        of outputstream_file:
            let file = open(desc.path, fmWrite)
            result = MMIOFileStream(file: file, write: true)
        of stream_stdin:
            result = MMIOFileStream(file: stdin, read: true)
        of stream_stdout:
            result = MMIOFileStream(file: stdout, write: true)
        of constant:
            result = MMIOConstant(value: desc.value)
