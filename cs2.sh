#!/bin/bash

GAMEROOT="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)"
SCRIPTNAME="$(basename "$0")"

[[ "$*" == *"-dedicated"* ]] && DEDICATED_SERVER=1 || DEDICATED_SERVER=0

UNAMEPATH="$(command -v uname)"
if [ -z "$UNAMEPATH" ]; then
    if [ -f /usr/bin/uname ]; then
        UNAMEPATH=/usr/bin/uname
    elif [ -f /bin/uname ]; then
        UNAMEPATH=/bin/uname
    fi
fi
UNAME="$($UNAMEPATH)"
if [ "$UNAME" = "Darwin" ]; then
   if [ "$STEAM_DYLD_INSERT_LIBRARIES" != "" ] && [ "$DYLD_INSERT_LIBRARIES" == "" ]; then
      export DYLD_INSERT_LIBRARIES="$STEAM_DYLD_INSERT_LIBRARIES"
   fi
   export DYLD_LIBRARY_PATH="${GAMEROOT}"/bin/osx64:$DYLD_LIBRARY_PATH
elif [ "$UNAME" = "Linux" ]; then
    . /etc/os-release
    if [ "$DEDICATED_SERVER" = "0" ] && [ "$VERSION_CODENAME" != "sniper" ]; then
        echo
        echo "FATAL: It appears $SCRIPTNAME was not launched within the Steam for Linux sniper runtime environment."
        echo "FATAL: Please consult documentation to ensure correct configuration, aborting."
        echo
        exit 1
    fi

   export LD_LIBRARY_PATH="${GAMEROOT}"/bin/linuxsteamrt64:$LD_LIBRARY_PATH
   USE_STEAM_RUNTIME=1
fi

if [ -z "$GAMEEXE" ]; then
   if [ "$UNAME" = "Darwin" ]; then
      GAMEEXE=bin/osx64/cs2.app/Contents/MacOS/cs2
   elif [ "$UNAME" = "Linux" ]; then
      GAMEEXE=bin/linuxsteamrt64/cs2
   fi
fi

ulimit -n 65535
ulimit -Ss 2048

cd "$GAMEROOT"

if [ "$UNAME" = "Linux" ]; then
    export ENABLE_PATHMATCH=1
fi

if [ "$UNAME" = "Linux" ]; then
    export SDL_VIDEO_DRIVER=wayland
fi

STATUS=42
while [ $STATUS -eq 42 ]; do
    if [ "${GAME_DEBUGGER}" == "gdb" ] || [ "${GAME_DEBUGGER}" == "cgdb" ]; then
        ARGSFILE=$(mktemp "$USER.cs2.gdb.XXXX")
        echo b main > "$ARGSFILE"
        echo set env LD_PRELOAD=$LD_PRELOAD >> "$ARGSFILE"
        echo show env LD_PRELOAD >> "$ARGSFILE"
        unset LD_PRELOAD
        echo run $@ >> "$ARGSFILE"
        echo show args >> "$ARGSFILE"
        ${GAME_DEBUGGER} "${GAMEROOT}"/${GAMEEXE} -x "$ARGSFILE"
        rm "$ARGSFILE"
    elif [ "${GAME_DEBUGGER}" == "lldb" ]; then
        ${GAME_DEBUGGER} "${GAMEROOT}"/${GAMEEXE} --$@
    else
        ${STEAM_RUNTIME_PREFIX} ${GAME_DEBUGGER} "${GAMEROOT}"/${GAMEEXE} "$@"
    fi
    STATUS=$?
done
exit $STATUS
