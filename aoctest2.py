import ctypes
from ctypes import wintypes

# Windows APIの準備
kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)

GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
OPEN_EXISTING = 3

# カーネル内のシンボリックリンク \\DosDevices\MyDrv を Win32 パス指定で開く
device_path = r"\\.\MyDrv"

print(f"[+] {device_path} への接続を試みます...")

handle = kernel32.CreateFileW(
    device_path,
    GENERIC_READ | GENERIC_WRITE,
    0,     # 共有モード (なし)
    None,  # セキュリティ属性
    OPEN_EXISTING,
    0,     # フラグ・属性
    None
)

if handle == -1 or handle == 0xFFFFFFFFFFFFFFFF:
    error_code = ctypes.get_last_error()
    print(f"[-] 接続失敗。エラーコード: {error_code}")
    if error_code == 2:
        print("    -> ファイルが見つかりません（リンク名が不整合の可能性）")
    elif error_code == 5:
        print("    -> アクセス拒否（管理者権限で実行してください）")
else:
    print(f"[+] 接続成功！ ハンドルを取得しました: {handle}")
    
    # 最後に必ずハンドルを閉じる（DriverUnloadを安全に行うため）
    kernel32.CloseHandle(handle)
    print("[+] ハンドルを正常に閉じました。")