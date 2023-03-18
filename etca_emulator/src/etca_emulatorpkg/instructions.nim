import std/strformat
import patty

type
    BaseOpcode* {.pure.} = enum
        Add = 0
        Sub = 1
        RSub = 2
        Comp = 3
        Or = 4
        Xor = 5
        And = 6
        Test = 7
        Movz = 8
        Movs = 9
        Load = 10
        Store = 11
        Slo = 12
        Push = 13
        ReadCR = 14
        WriteCR = 15
        Pop = 16 # Actually 12
    ConditionCode* {.pure.} = enum
        Z = 0
        NZ = 1
        N = 2
        NN = 3
        C = 4
        NC = 5
        V = 6
        NV = 7
        BE = 8
        A = 9
        LT = 10
        GE = 11
        LE = 12
        GT = 13
        ALWAYS = 14
        NEVER = 15

    RegisterIndex* = range[0..16]

    BitWidth* = enum
        w8 = 8
        w16 = 16
        w32 = 32
        w64 = 64

func byte_count*(w: BitWidth): int =
    case w:
        of w8:
            1
        of w16:
            2
        of w32:
            4
        of w64:
            8


const NoStore* = {BaseOpcode.Comp, BaseOpcode.Test, BaseOpcode.Store, BaseOpcode.WriteCR, BaseOpcode.Push}
const SignExtend* = {BaseOpcode.Add .. BaseOpcode.Test, BaseOpcode.Movs}
const ZeroExtend* = {BaseOpcode.Movz, BaseOpcode.Store .. BaseOpcode.WriteCR}

variantp Instruction:
    BaseRegReg(brr_opcode: BaseOpcode, rr_size: BitWidth, rr_a: RegisterIndex, rr_b: RegisterIndex)
    BaseRegImm(bri_opcode: BaseOpcode, ri_size: BitWidth, ri_a: RegisterIndex, ri_b: uint64)
    BaseJump(bj_cond: ConditionCode, bj_displacment: int64, bj_orig_width: uint8)
    SafCallImm(sci_displacment: int64)
    SafCondJumpCall(scjc_cond: ConditionCode, scjc_register: RegisterIndex, scjc_is_call: bool)


const MAX_INSTRUCTION_LENGTH* = 2

const sizes = [w8, w16, w32, w64]

func decodeInstruction*(buffer: seq[uint8]): tuple[consumed: uint, res: Instruction] =
    doAssert buffer.len >= MAX_INSTRUCTION_LENGTH
    case (buffer[0] and 0xC0) shr 6:
        of 0b00:
            let size = sizes[(buffer[0] and 0x30) shr 4]
            var opcode = BaseOpcode(buffer[0] and 0x0F)
            let a = RegisterIndex((buffer[1] shr 5) and 0x07)
            let b = RegisterIndex((buffer[1] shr 2) and 0x07)
            let mm = buffer[1] and 0x03
            if mm != 0:
                raise newException(ValueError, fmt"Unsupported Memory Operands mode {mm}")
            if opcode == Slo:
                if b != 6:
                    raise newException(ValueError, "asp is not supported")
                opcode = Pop
            if opcode == Push and a != 6:
                raise newException(ValueError, "asp is not supported")
            if opcode in {ReadCr, WriteCr}:
                raise newException(ValueError, fmt"Invalid opcode for RegReg mode {opcode}")
            return (2'u, BaseRegReg(opcode, size, a, b))
        of 0b01:
            let size = sizes[(buffer[0] and 0x30) shr 4]
            let opcode = BaseOpcode(buffer[0] and 0x0F)
            let a = RegisterIndex((buffer[1] shr 5) and 0x07)
            var imm: uint64 = buffer[1] and 0x1F
            if opcode in SignExtend and ((imm and 0x10) != 0):
                imm = 0xFFFFFFFFFFFFFFF0'u64 or imm
            return (2'u, BaseRegImm(opcode, size, a, imm))
        of 0b10:
            if (buffer[0] and 0x20) != 0: # Saf Call or Jump
                if (buffer[0] and 0x10) != 0:
                    var displacement = ((buffer[0] and 0x0F'u64) shl 8) or buffer[1] 
                    displacement = (if (displacement and 0x800) != 0: 0xFFFFFFFFFFFFF000'u64 else: 0) or displacement
                    return (2'u, SafCallImm(cast[int64](displacement)))
                else:
                    let cond = ConditionCode(buffer[1] and 0x0F)
                    let reg = RegisterIndex((buffer[1] shr 5) and 0x07)
                    return (2'u, SafCondJumpCall(cond, reg, (buffer[1] and 0x10) != 0))
            else:
                let displacement  = (if (buffer[0] and 0x10) != 0: 0xFFFFFFFFFFFFFF00'u64 else: 0) or buffer[1].uint64
                if (buffer[0] and 0x10) != 0:
                    doAssert cast[int64](displacement) < 0
                let cond = ConditionCode(buffer[0] and 0x0F)
                return (2'u, BaseJump(cond, cast[int64](displacement), 9))
        else:
            raise newException(ValueError, fmt"Unknown instruction {buffer[0]:02X}")