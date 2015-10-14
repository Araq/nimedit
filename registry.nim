
import winlean, os

type
  HKEY* = uint

const
  HKEY_CLASSES_ROOT* =     HKEY(0x80000000u)
  HKEY_CURRENT_USER* =     HKEY(0x80000001u)
  HKEY_LOCAL_MACHINE* =    HKEY(0x80000002u)
  HKEY_USERS* =            HKEY(0x80000003u)
  HKEY_PERFORMANCE_DATA* = HKEY(0x80000004u)
  HKEY_CURRENT_CONFIG* =   HKEY(0x80000005u)
  HKEY_DYN_DATA* =         HKEY(0x80000006u)

  RRF_RT_ANY = 0x0000ffff
  KEY_WOW64_64KEY = 0x0100
  KEY_WOW64_32KEY = 0x0200

  REG_SZ = 1
  REG_BINARY = 3

when false:
  const
    REG_NONE = 0
    REG_EXPAND_SZ = 2
    REG_DWORD = 4
    REG_DWORD_LITTLE_ENDIAN = 4
    REG_DWORD_BIG_ENDIAN = 5
    REG_LINK = 6
    REG_MULTI_SZ = 7
    REG_RESOURCE_LIST = 8
    REG_FULL_RESOURCE_DESCRIPTOR = 9
    REG_RESOURCE_REQUIREMENTS_LIST = 10
    REG_QWORD = 11
    REG_QWORD_LITTLE_ENDIAN = 11

proc regConnectRegistry(lpMachineName: WideCString,
              hKey: HKEY, phkResult: var HKEY): int32 {.
              importc: "RegConnectRegistryW", dynlib: "Advapi32.dll", stdcall.}

proc regCloseKey(hkey: HKEY): int32 {.
  importc: "RegCloseKey", dynlib: "Advapi32.dll", stdcall.}

proc regGetValue(key: HKEY, lpSubKey, lpValue: WideCString;
                 dwFlags: int32 = RRF_RT_ANY, pdwType: ptr int32,
                 pvData: pointer,
                 pcbData: ptr int32): int32 {.
  importc: "RegGetValueW", dynlib: "Advapi32.dll", stdcall.}


proc regSetValue(hKey: HKEY, lpSubKey: WideCString, dwType: int32,
                 lpData: pointer, cbData: int32): int32 {.
  importc: "RegSetValueW", dynlib: "Advapi32.dll", stdcall.}

proc regSetValueEx(hKey: HKEY, lpValueName: WideCString, reserved: int32,
                   dwType: int32, lpData: pointer, cbData: int32): int32 {.
  importc: "RegSetValueExW", dynlib: "Advapi32.dll", stdcall.}

proc open*(hKey = HKEY_CURRENT_USER): HKEY =
  ## Opens a connection to the registry. Usually not required.
  if regConnectRegistry(nil, hKey, result) != 0:
    raiseOSError(osLastError())

proc close*(handle: HKEY) =
  ## Closes the connection.
  if regCloseKey(handle) != 0:
    raiseOSError(osLastError())

proc getUnicodeValue*(key: string; handle: HKEY = HKEY_CURRENT_USER): string =
  let hh = newWideCString key
  var bufsize: int32
  # try a couple of different flag settings:
  var flags: int32 = RRF_RT_ANY
  if regGetValue(handle, hh, nil, flags, nil, nil, addr bufsize) != 0:
    raiseOSError(osLastError())
  var res = newWideCString("", bufsize)
  if regGetValue(handle, hh, nil, flags, nil, cast[pointer](res),
                 addr bufsize) != 0:
    raiseOSError(osLastError())
  result = res $ bufsize

proc getBlobValue*(key: string; handle: HKEY = HKEY_CURRENT_USER): string =
  let hh = newWideCString key
  var bufsize: int32
  # try a couple of different flag settings:
  var flags: int32 = RRF_RT_ANY or 0x00010000
  if regGetValue(handle, hh, nil, flags, nil, nil, addr bufsize) != 0:
    raiseOSError(osLastError())
  result = newString(bufsize)
  if regGetValue(handle, hh, nil, flags, nil, addr result[0],
                 addr bufsize) != 0:
    raiseOSError(osLastError())

proc setUnicodeValue*(key, value: string; handle: HKEY = HKEY_CURRENT_USER) =
  if regSetValue(handle, newWideCString key, REG_SZ,
                 cast[pointer](newWideCString value), value.len.int32*2) != 0:
    raiseOSError(osLastError())

proc setBlobValue*(key, value: string; handle: HKEY = HKEY_CURRENT_USER) =
  if regSetValueEx(handle, newWideCString key, 0, REG_BINARY,
                 cast[pointer](cstring(value)), value.len.int32) != 0:
    raiseOSError(osLastError())

proc setBlobValue*(key: string, value: pointer; valueLen: Natural;
                   handle: HKEY = HKEY_CURRENT_USER) =
  if regSetValueEx(handle, newWideCString key, 0, REG_BINARY,
                 value, valueLen.int32) == 0:
    raiseOSError(osLastError())

when isMainModule:
  #let x = open()
  #setUnicodeValue(r"Software\TestAndreas\ProductKey", "abc", HKEY_CURRENT_USER)
  echo getUnicodeValue(r"Software\TestAndreas\ProductKey") #, HKEY_CURRENT_USER)
  #echo getUnicodeValue(r"hardware\acpi\facs\00000000") #, HKEY_CURRENT_USER)
  #discard stdin.readline()
  #echo getUnicodeValue(r"Software\Microsoft\Windows\CurrentVersion\GameInstaller")
 #   HKEY_CURRENT_USER)
  var data = [64'u8, 65'u8, 66'u8]
  setBlobValue(r"Software\TestAndreas\ProductID", addr data, 3)
  echo getBlobValue(r"Software\TestAndreas\ProductID")

  #echo getUnicodeValue(r"Software\Microsoft\Windows\CurrentVersion\DigitalProductId")
#  echo getUnicodeValue(r"SOFTWARE\Wow6432Node\Microsoft\Cryptography\MachineGuid")
  #echo getValue(r"Software\Wow6432Node\7-Zip\Path")
  #x.close
