import ctypes
import ctypes.wintypes as wt

# 定数
GENERIC_READ        = 0x80000000
GENERIC_WRITE       = 0x40000000
OPEN_EXISTING       = 3
INVALID_HANDLE      = ctypes.c_void_p(-1).value

# IOCTLコード（ドライバ側と合わせる）
IOCTL_READ_MSR  = 0x80002000
IOCTL_WRITE_MSR = 0x80002004

k32 = ctypes.windll.kernel32

# デバイスを開く
hDevice = k32.CreateFileW(
    r"\\.\MyDrv",
    GENERIC_READ | GENERIC_WRITE,
    0, None,
    OPEN_EXISTING,
    0, None
)
if hDevice == INVALID_HANDLE:
    raise ctypes.WinError()

# バッファ定義（ドライバ側のオフセットと一致させる）
class MsrRequest(ctypes.Structure):
    _fields_ = [
        ("MsrAddress", ctypes.c_uint32),
        ("_pad",       ctypes.c_uint32),
        ("Value",      ctypes.c_uint64),
    ]

def read_msr(address: int) -> int:
    buf = MsrRequest()
    buf.MsrAddress = address
    returned = wt.DWORD(0)

    ok = k32.DeviceIoControl(
        hDevice,
        IOCTL_READ_MSR,
        ctypes.byref(buf), ctypes.sizeof(buf),  # 入力
        ctypes.byref(buf), ctypes.sizeof(buf),  # 出力（同じバッファ）
        ctypes.byref(returned),
        None
    )
    if not ok:
        raise ctypes.WinError()
    return buf.Value

def write_msr(address: int, value: int):
    buf = MsrRequest()
    buf.MsrAddress = address
    buf.Value      = value
    returned = wt.DWORD(0)

    ok = k32.DeviceIoControl(
        hDevice,
        IOCTL_WRITE_MSR,
        ctypes.byref(buf), ctypes.sizeof(buf),
        ctypes.byref(buf), ctypes.sizeof(buf),
        ctypes.byref(returned),
        None
    )
    if not ok:
        raise ctypes.WinError()

# 使用例：Ryzen P-state 0を読む
val = read_msr(0xC0010064)
print(f"P-state 0: 0x{val:016X}")