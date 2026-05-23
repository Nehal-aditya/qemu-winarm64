; installer.nsi — Production build
; All instructions are single-line (NSIS has no line-continuation syntax).
; StrFunc.nsh is NOT used in the Uninstall section — its generated functions
; lack the required "un." prefix and cause a compile error there.
; Traversal detection and case-insensitive comparison use inline NSIS only.

!include "LogicLib.nsh"
!include "WinMessages.nsh"

; --------------------------------------------------------------------------
; Defines
; --------------------------------------------------------------------------
!define APPNAME      "QEMU ARM64"
!define APPNAME_KEY  "QEMUArm64"
!define COMPANY      "Custom Build Pipeline"
!define DESCRIPTION  "Native QEMU System Emulator for Windows 11 ARM64"
!define VERSION      "1.0.0"
!define REG_KEY      "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME_KEY}"
!define SENTINEL     "qemu-system-aarch64.exe"
!define MIN_PATH_LEN 30

; --------------------------------------------------------------------------
; Installer metadata
; --------------------------------------------------------------------------
Name    "${APPNAME}"
OutFile "qemu-user-setup.exe"
RequestExecutionLevel user
InstallDir "$LOCALAPPDATA\Programs\qemu"

Page directory
Page instfiles

; --------------------------------------------------------------------------
; Global variables
; --------------------------------------------------------------------------
Var PathCheck
Var PathLen
Var LastChar
Var CmpResult
Var UserProfile     ; populated at runtime from the USERPROFILE environment variable

; --------------------------------------------------------------------------
; Macro: NotifyPathChange
; --------------------------------------------------------------------------
!macro NotifyPathChange
    SendMessage ${HWND_BROADCAST} ${WM_SETTINGCHANGE} 0 "STR:Environment" /TIMEOUT=500
!macroend

; --------------------------------------------------------------------------
; Macro: AbortMsg — message box + Quit, centralised so Quit is never missed.
; --------------------------------------------------------------------------
!macro AbortMsg MSG
    MessageBox MB_OK|MB_ICONSTOP "${MSG}"
    Quit
!macroend

; --------------------------------------------------------------------------
; Macro: PathContainsDotDot
; Checks whether a path string contains ".." using a character-by-character
; scan — no StrFunc.nsh required, works in both Install and Uninstall.
; Sets $CmpResult to 1 if ".." found, 0 if not.
; Uses $0/$1/$2 internally (saves/restores them).
; --------------------------------------------------------------------------
!macro PathContainsDotDot PATH
    Push $0
    Push $1
    Push $2
    StrCpy $CmpResult 0
    StrCpy $0 "${PATH}"   ; string to scan
    _dotdot_loop:
        StrCpy $1 $0 2    ; take first 2 chars
        ${If} $1 == ".."
            StrCpy $CmpResult 1
            Goto _dotdot_done
        ${EndIf}
        StrCpy $2 $0 1    ; take 1 char (check if we've reached end)
        ${If} $2 == ""
            Goto _dotdot_done
        ${EndIf}
        StrCpy $0 $0 "" 1 ; advance by 1 character
        Goto _dotdot_loop
    _dotdot_done:
    Pop $2
    Pop $1
    Pop $0
!macroend

; --------------------------------------------------------------------------
; Macro: CaseInsensitiveEq
; Case-insensitive string comparison using the Windows API lstrcmpiA.
; Sets $CmpResult to 1 if strings are equal (ignoring case), 0 if not.
; lstrcmpiA is always available — no plugins required.
; --------------------------------------------------------------------------
!macro CaseInsensitiveEq STR_A STR_B
    System::Call 'kernel32::lstrcmpiA(t "${STR_A}", t "${STR_B}") i .s'
    Pop $CmpResult
    ; lstrcmpiA returns 0 if equal — invert to make 1=equal, 0=not equal
    ${If} $CmpResult == 0
        StrCpy $CmpResult 1
    ${Else}
        StrCpy $CmpResult 0
    ${EndIf}
!macroend

; ==========================================================================
; Install section
; ==========================================================================
Section "Install"
    SetShellVarContext current
    SetOutPath "$INSTDIR"
    File /r "qemu-windows-arm64\*"

    ; Start Menu shortcuts
    CreateDirectory "$SMPROGRAMS\${APPNAME}"
    CreateShortcut "$SMPROGRAMS\${APPNAME}\QEMU System AArch64.lnk" "$INSTDIR\qemu-system-aarch64.exe" "" "$INSTDIR\qemu-system-aarch64.exe" 0
    CreateShortcut "$SMPROGRAMS\${APPNAME}\QEMU System x86_64.lnk" "$INSTDIR\qemu-system-x86_64.exe" "" "$INSTDIR\qemu-system-x86_64.exe" 0

    ; Uninstall registry entries (HKCU — no admin required)
    WriteRegStr HKCU "${REG_KEY}" "DisplayName"     "${APPNAME}"
    WriteRegStr HKCU "${REG_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
    WriteRegStr HKCU "${REG_KEY}" "DisplayVersion"  "${VERSION}"
    WriteRegStr HKCU "${REG_KEY}" "Publisher"       "${COMPANY}"
    WriteRegStr HKCU "${REG_KEY}" "InstallLocation" "$INSTDIR"

    ; --- PATH modification (HKCU\Environment only) ---
    ; EnVar::SetHKCU pushes a return code — pop immediately.
    ; EnVar::Check: 0=present, 1=absent, 2=error
    ; EnVar::AddValue: 0=ok, non-zero=failure
    EnVar::SetHKCU
    Pop $PathCheck

    EnVar::Check "PATH" "$INSTDIR"
    Pop $PathCheck

    ${If} $PathCheck == 1
        EnVar::AddValue "PATH" "$INSTDIR"
        Pop $PathCheck
        ${If} $PathCheck <> 0
            MessageBox MB_OK|MB_ICONEXCLAMATION "Warning: could not add to PATH (EnVar error $PathCheck).$\nPlease add '$INSTDIR' to your user PATH manually."
        ${EndIf}
    ${ElseIf} $PathCheck == 2
        MessageBox MB_OK|MB_ICONEXCLAMATION "Warning: could not read the PATH variable (EnVar error $PathCheck).$\nPlease add '$INSTDIR' to your user PATH manually."
    ${EndIf}

    !insertmacro NotifyPathChange
    WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

; ==========================================================================
; Uninstall section
; ==========================================================================
Section "Uninstall"
    SetShellVarContext current

    ReadRegStr $INSTDIR HKCU "${REG_KEY}" "InstallLocation"

    ; === GUARD 1: path must not be empty ===
    ${If} $INSTDIR == ""
        !insertmacro AbortMsg "Uninstall aborted: install location not found in registry.$\nIf QEMU is still installed, please remove it manually."
    ${EndIf}

    ; === GUARD 2: path must meet minimum length (IntCmp = integer, not string compare) ===
    StrLen $PathLen "$INSTDIR"
    IntCmp $PathLen ${MIN_PATH_LEN} path_too_short path_too_short path_len_ok
    path_too_short:
        !insertmacro AbortMsg "Uninstall aborted: stored path '$INSTDIR' is too short to be a valid install location."
    path_len_ok:

    ; === GUARD 3: path must not end with a backslash ===
    StrCpy $LastChar "$INSTDIR" 1 -1
    ${If} $LastChar == "\"
        !insertmacro AbortMsg "Uninstall aborted: stored path '$INSTDIR' ends with a backslash (possible drive root)."
    ${EndIf}

    ; === GUARD 4: path must not contain traversal sequences (..) ===
    ; Uses inline character scan — no StrFunc.nsh needed.
    !insertmacro PathContainsDotDot "$INSTDIR"
    ${If} $CmpResult == 1
        !insertmacro AbortMsg "Uninstall aborted: stored path '$INSTDIR' contains a path traversal sequence (..)."
    ${EndIf}

    ; === GUARD 5: path must not equal LOCALAPPDATA root (case-insensitive) ===
    ; Uses lstrcmpiA via System::Call — no StrFunc.nsh needed.
    !insertmacro CaseInsensitiveEq "$INSTDIR" "$LOCALAPPDATA"
    ${If} $CmpResult == 1
        !insertmacro AbortMsg "Uninstall aborted: stored path '$INSTDIR' resolves to the LOCALAPPDATA root."
    ${EndIf}

    ; === GUARD 6: path must not equal USERPROFILE root (case-insensitive) ===
    !insertmacro CaseInsensitiveEq "$INSTDIR" "$USERPROFILE"
    ${If} $CmpResult == 1
        !insertmacro AbortMsg "Uninstall aborted: stored path '$INSTDIR' resolves to the user profile root."
    ${EndIf}

    ; === GUARD 7: sentinel file must exist ===
    ${IfNot} ${FileExists} "$INSTDIR\${SENTINEL}"
        !insertmacro AbortMsg "Uninstall aborted: '$INSTDIR\${SENTINEL}' not found.$\nThis does not appear to be a valid QEMU installation."
    ${EndIf}

    ; --- Remove only our PATH entry (HKCU, surgical) ---
    EnVar::SetHKCU
    Pop $PathCheck

    EnVar::DeleteValue "PATH" "$INSTDIR"
    Pop $PathCheck
    ${If} $PathCheck == 2
        MessageBox MB_OK|MB_ICONEXCLAMATION "Warning: could not remove from PATH (EnVar error $PathCheck).$\nPlease remove '$INSTDIR' from your user PATH manually."
    ${EndIf}

    !insertmacro NotifyPathChange

    Delete "$INSTDIR\uninstall.exe"
    RMDir /r /REBOOTOK "$INSTDIR"
    RMDir /r /REBOOTOK "$SMPROGRAMS\${APPNAME}"
    DeleteRegKey HKCU "${REG_KEY}"
SectionEnd
