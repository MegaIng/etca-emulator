import instructions
import memory_maps
import patty
import std/sequtils
import std/strformat



type
    Register* = uint64

    Flags* = tuple
        Z: bool
        N: bool
        C: bool
        V: bool

    DebugFlag* = enum
        log_instructions
        log_instruction_buffer
        log_memory_access
        log_flags
        log_alu
        log_registers

    DebugFlags* = set[DebugFlag]

    CPU* = object
        registers*: array[RegisterIndex, Register]
        flags: Flags
        address_width*: BitWidth
        pc*: Register

        debug*: DebugFlags

        halted: bool
        buffer_offset: uint
        instruction_buffer: seq[uint8]
        memory*: MemoryMap
    

proc build_cpu*(memory: MemoryMap): CPU =
    result.memory = memory
    result.pc = 0xFFFF_FFFF_FFFF_8000'u64
    result.address_width = w16

proc get_real_address*(cpu: var CPU, address: uint64): uint64 = 
    let mask = (1'u64 shl cpu.address_width.ord) - 1
    let sign_bit = (1'u64 shl (cpu.address_width.ord - 1))
    if (address and sign_bit) != 0:
        result = (not mask) or address
    else:
        result = mask and address

proc mem_get*(cpu: var CPU, address: uint64, width: BitWidth): uint64 =
    let real_address = cpu.get_real_address(address)
    result = cpu.memory.get(real_address, width)
    if log_memory_access in cpu.debug:
        echo fmt"{address:016X} -> {real_address:016X}: read {width}: {result:016X}"


proc mem_set*(cpu: var CPU, address: uint64, width: BitWidth, value: uint64) =
    let real_address = cpu.get_real_address(address)
    cpu.memory.set(real_address, width, value)
    if log_memory_access in cpu.debug:
        echo fmt"{address:016X} -> {real_address:016X}: write {width}: {value:016X}"

proc check*(cpu: var CPU, cond: ConditionCode): bool =
    case cond:
        of Z:
            return cpu.flags.Z
        of NZ:
            return not cpu.flags.Z
        of N:
            return cpu.flags.N
        of NN:
            return not cpu.flags.N
        of C:
            return cpu.flags.C
        of NC:
            return not cpu.flags.C
        of V:
            return cpu.flags.V
        of NV:
            return not cpu.flags.V
        of BE:
            return cpu.flags.C or cpu.flags.Z
        of A:
            return not (cpu.flags.C or cpu.flags.Z)
        of LT:
            return cpu.flags.N != cpu.flags.V
        of GE:
            return cpu.flags.N == cpu.flags.V
        of LE:
            return cpu.flags.Z or (cpu.flags.N != cpu.flags.V)
        of GT:
            return not(cpu.flags.Z or (cpu.flags.N != cpu.flags.V))
        of ALWAYS:
            return true
        of NEVER:
            return false


proc compute*(cpu: var CPU, opcode: BaseOpcode, width: BitWidth, arg1: uint64, arg2: uint64): uint64 =
    let sign_bit = (1'u64 shl (width.ord - 1))
    let mask = (1'u64 shl width.ord) - 1
    var set_flags: bool = false
    case opcode:
        of Add, Sub, Rsub, Comp:
            set_flags = true
            let carry_bit = (1'u64 shl width.ord)

            var a = if opcode in {Add, Sub, Comp}: arg1 else: not arg1
            var b = if opcode in {Add, Rsub}: arg2 else: not arg2
            var c = uint64(opcode in {Sub, Rsub, Comp})
            a = a and mask
            b = b and mask

            let a_sign = a and sign_bit
            let b_sign = b and sign_bit

            result = a + b + c
            if width != w64:
                cpu.flags.C = (result and carry_bit) != 0
            else:
                cpu.flags.C = result < a
            if opcode in {Sub, RSub, Comp}:
                cpu.flags.C = not cpu.flags.C
            cpu.flags.V = (a_sign == b_sign) and ((result and sign_bit) != a_sign)
        of And, Test:
            result = arg1 and arg2
            set_flags = true
        of Or:
            result = arg1 or arg2
            set_flags = true
        of Xor:
            result = arg1 xor arg2
            set_flags = true
        of Movs, Movz:
            result = arg2
        of Load:
            result = cpu.mem_get(arg2, width)
        of Store:
            cpu.mem_set(arg2, width, arg1)
        of Slo:
            result = (arg1 shl 5) or arg2
        of Push:
            if log_memory_access in cpu.debug:
                echo "Push"
            cpu.mem_set(cpu.registers[6], width, arg2)
            cpu.registers[6] -= byte_count(width).uint64
        of Pop:
            if log_memory_access in cpu.debug:
                echo "Pop"
            cpu.registers[6] += byte_count(width).uint64
            result = cpu.mem_get(cpu.registers[6], width)
        else:
            raise newException(ValueError, fmt"Opcode not implemented {opcode}")
    result = result and mask
    if set_flags:
        cpu.flags.Z = result == 0
        cpu.flags.N = (result and sign_bit) != 0
    if opcode != Movz and ((result and sign_bit) != 0):
        result = result or not mask

proc step*(cpu: var CPU) =
    while cpu.instruction_buffer.len < MAX_INSTRUCTION_LENGTH:
        let data = cpu.mem_get(cpu.pc + cpu.buffer_offset, w64)
        cpu.buffer_offset += 8
        for i in 0..7:
            cpu.instruction_buffer.add uint8((data shr (8*i)) and 0xFF)
    let (length, inst) = decodeInstruction(cpu.instruction_buffer)
    if cpu.debug.len > 0:
        echo ""
    if log_instruction_buffer in cpu.debug:
         echo fmt"{cpu.pc:016X}", cpu.instruction_buffer
    if log_flags in cpu.debug:
        echo fmt"{cpu.flags}"
    if log_registers in cpu.debug:
        stdout.write '['
        for r in cpu.registers:
            stdout.write fmt"{r: 17X} "
        stdout.write ']'
        stdout.write '\n'
    if log_instructions in cpu.debug:
        echo fmt"{cpu.pc:016X}", inst
    let start_pc = cpu.pc
    var did_jump = false
    match inst:
        BaseRegReg(opcode, size, a, b):
            let arg1 = cpu.registers[a]
            let arg2 = cpu.registers[b]
            let res = cpu.compute(opcode, size, arg1, arg2)
            if opcode notin NoStore:
                cpu.registers[a] = res
        BaseRegImm(opcode, size, a, imm):
            let arg1 = cpu.registers[a]
            let arg2 = imm
            let res = cpu.compute(opcode, size, arg1, arg2)
            if opcode notin NoStore:
                cpu.registers[a] = res
        BaseJump(cond, displacment):
            if cpu.check(cond):
                did_jump = true
                cpu.pc += displacment.uint64
                if displacment == 0:
                    cpu.halted = true
        SafCallImm(displacement):
            did_jump = true
            cpu.registers[7] = cpu.pc + length
            cpu.pc += displacement.uint64
        SafCondJumpCall(cond, reg, is_call):
            if cpu.check(cond):
                did_jump = true
                let temp = cpu.pc
                cpu.pc = cpu.registers[reg]
                if is_call:
                    cpu.registers[7] = temp + length
    if not did_jump:
        cpu.pc += length
        cpu.buffer_offset -= length
        cpu.instruction_buffer.delete(0 .. (length.int-1))
    else:
        cpu.buffer_offset = 0
        cpu.instruction_buffer.setLen 0
    # if cpu.pc < 0xFFFF_FFFF_FFFF_8000'u64:
    #     cpu.debug = {log_instructions, log_memory_access, log_registers}


proc run*(cpu: var CPU) =
    while not cpu.halted:
        cpu.step()
