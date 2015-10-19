## Module to retrieve a globally unique machine ID.

when defined(windows):
  import winlean, os

  type
    HKEY* = uint

  const
    HKEY_LOCAL_MACHINE = HKEY(0x80000002u)

    RRF_RT_ANY = 0x0000ffff
    KEY_WOW64_64KEY = 0x0100
    KEY_WOW64_32KEY = 0x0200
    KEY_READ = 0x00020019

  proc regOpenKeyEx(hKey: HKEY, lpSubKey: WideCString, ulOptions: int32,
                    samDesired: int32,
                    phkResult: var HKEY): int32 {.
    importc: "RegOpenKeyExW", dynlib: "Advapi32.dll", stdcall.}

  proc regCloseKey(hkey: HKEY): int32 {.
    importc: "RegCloseKey", dynlib: "Advapi32.dll", stdcall.}

  proc regGetValue(key: HKEY, lpSubKey, lpValue: WideCString;
                   dwFlags: int32 = RRF_RT_ANY, pdwType: ptr int32,
                   pvData: pointer,
                   pcbData: ptr int32): int32 {.
    importc: "RegGetValueW", dynlib: "Advapi32.dll", stdcall.}

  template call(f) =
    let err = f
    if err != 0:
      raiseOSError(err.OSErrorCode, astToStr(f))

  proc getUnicodeValue(a, b: string; handle: HKEY): string =
    let hh = newWideCString a
    let kk = newWideCString b
    var bufsize: int32
    # try a couple of different flag settings:
    var flags: int32 = RRF_RT_ANY
    let err = regGetValue(handle, hh, kk, flags, nil, nil, addr bufsize)
    if err != 0:
      var newHandle: HKEY
      call regOpenKeyEx(handle, hh, 0, KEY_READ or KEY_WOW64_64KEY, newHandle)
      call regGetValue(newHandle, nil, kk, flags, nil, nil, addr bufsize)
      var res = newWideCString("", bufsize)
      call regGetValue(newHandle, nil, kk, flags, nil, cast[pointer](res),
                     addr bufsize)
      result = res $ bufsize
      call regCloseKey(newHandle)
    else:
      var res = newWideCString("", bufsize)
      call regGetValue(handle, hh, kk, flags, nil, cast[pointer](res),
                     addr bufsize)
      result = res $ bufsize

  proc getMachineGuid*(): string =
    result = getUnicodeValue(r"SOFTWARE\Microsoft\Cryptography", "MachineGuid",
      HKEY_LOCAL_MACHINE)

elif defined(linux) or defined(bsd):
  from strutils import strip

  proc getMachineGuid*(): string = readFile("/etc/machine-id").strip

elif defined(macosx):
  import posix, os

  type
    uuid_t {.importc, header: "<unistd.h>".} = object
    uuid_string_t = array[37, char]

  proc gethostuuid(u: var uuid_t, wait: ptr Timespec): cint {.
    importc: "gethostuuid", header: "<unistd.h>", cdecl.}
  proc uuid_unparse(u: uuid_t, result: var uuid_string_t) {.importc,
    header: "<uuid/uuid.h>", cdecl.}

  proc getMachineGuid*(): string =
    var u: uuid_t
    var t: Timespec
    if gethostuuid(u, addr t) != 0: raiseOsError(osLastError())
    var s: uuid_string_t
    uuid_unparse(u, s)
    result = $s

else:
  {.error: "Unsupported OS.".}

when isMainModule:
  echo getMachineGuid()

