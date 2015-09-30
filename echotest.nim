
import os

if os.paramCount() >= 1:
  let doFlush = os.paramStr(1) == "flush"
  var i = 1
  while true:
    echo "Hello World! ", i
    if doFlush: flushFile(stdout)
    inc i
    os.sleep(300)
else:
  for i in 1..10:
    echo "Hello World! ", i

# FILE_TYPE_CHAR 0x0002
# tcsetattr
