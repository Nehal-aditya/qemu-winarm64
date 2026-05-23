; installer.nsi — Production build
; All instructions are single-line (NSIS has no line-continuation syntax).
; Named Var declarations prevent stack clobber from nested NSIS internals.

!include "LogicLib.nsh"
!include "WinMessages.nsh"
!include "StrFunc.nsh"
${StrStr}
${StrCase}

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
; Integer minimum — compared with IntCmp, not string ${If}, so no string-sort bug.
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
; Global variables — declared before any Section or Function.
; Using named Var avoids accidental clobber: NSIS built-ins reuse $0/$1/$2.
; --------------------------------------------------------------------------
Var PathCheck
Var PathLen
Var LastChar
Var TraversalCheck
Var InstDirLower
Var LocalAppLower

; --------------------------------------------------------------------------
; Macro: NotifyPathChange
; Broadcasts WM_SETTINGCHANGE so Explorer and new cmd windows pick up the
; updated PATH without a reboot.  Single line — NSIS has no line continuation.
; --------------------------------------------------------------------------
!macro NotifyPathChange
    SendMessage ${HWND_BROADCAST} ${WM_SETTINGCHANGE} 0 "STR:Environment" /TIMEOUT=500
!macroend

; --------------------------------------------------------------------------
; Macro: AbortMsg
; Shows a stop-icon message box and calls Quit.
; Centralising Quit here means it can never be accidentally dropped.
; Usage: !insertmacro AbortMsg "message text"
; --------------------------------------------------------------------------
!macro AbortMsg MSG
    MessageBox MB_OK|MB_ICONSTOP "${MSG}"
    Quit
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
    ; No trailing backslash — keeps uninstall path comparisons consistent.
    WriteRegStr HKCU "${REG_KEY}" "InstallLocation" "$INSTDIR"

    ; --- PATH modification (HKCU\Environment only, never HKLM) -----------
    ;
    ; EnVar::SetHKCU pushes a return code — pop it immediately to keep the
    ; stack balanced.  Call SetHKCU right before each EnVar operation so a
    ; prior SetHKLM from another installer cannot bleed through.
    ;
    ; EnVar::Check codes: 0=present, 1=absent, 2=error
    ; EnVar::AddValue codes: 0=ok, non-zero=failure
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
    ; $PathCheck == 0 → already present, nothing to do

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

    ; === GUARD 2: path must meet minimum length (integer comparison) ===
    ; NSIS ${If} with <= uses string comparison, which gives wrong results for
    ; single-digit lengths ("9" > "30" as strings).  IntCmp is always numeric.
    ; IntCmp a b lt eq gt — jumps to lt label if a < b, eq if a == b, gt if a > b.
    StrLen $PathLen "$INSTDIR"
    IntCmp $PathLen ${MIN_PATH_LEN} path_too_short path_too_short path_ok
    path_too_short:
        !insertmacro AbortMsg "Uninstall aborted: stored path '$INSTDIR' is too short to be a valid install location."
    path_ok:

    ; === GUARD 3: path must not end with a backslash ===
    StrCpy $LastChar "$INSTDIR" 1 -1
    ${If} $LastChar == "\"
        !insertmacro AbortMsg "Uninstall aborted: stored path '$INSTDIR' ends with a backslash (possible drive root)."
    ${EndIf}

    ; === GUARD 4: path must not contain traversal sequences ===
    ${StrStr} $TraversalCheck "$INSTDIR" ".."
    ${If} $TraversalCheck != ""
        !insertmacro AbortMsg "Uninstall aborted: stored path '$INSTDIR' contains a path traversal sequence (..)."
    ${EndIf}

    ; === GUARD 5: path must not equal LOCALAPPDATA root (case-insensitive) ===
    ${StrCase} $InstDirLower "$INSTDIR" "L"
    ${StrCase} $LocalAppLower "$LOCALAPPDATA" "L"
    ${If} $InstDirLower == $LocalAppLower
        !insertmacro AbortMsg "Uninstall aborted: stored path '$INSTDIR' resolves to the LOCALAPPDATA root."
    ${EndIf}

    ; === GUARD 6: path must not equal USERPROFILE root (case-insensitive) ===
    ${StrCase} $TraversalCheck "$USERPROFILE" "L"
    ${If} $InstDirLower == $TraversalCheck
        !insertmacro AbortMsg "Uninstall aborted: stored path '$INSTDIR' resolves to the user profile root."
    ${EndIf}

    ; === GUARD 7: sentinel file must exist inside the directory ===
    ${IfNot} ${FileExists} "$INSTDIR\${SENTINEL}"
        !insertmacro AbortMsg "Uninstall aborted: '$INSTDIR\${SENTINEL}' not found.$\nThis does not appear to be a valid QEMU installation."
    ${EndIf}

    ; --- Remove only our PATH entry, surgically (HKCU only) ---------------
    EnVar::SetHKCU
    Pop $PathCheck

    EnVar::DeleteValue "PATH" "$INSTDIR"
    Pop $PathCheck
    ; 0=removed, 1=wasn't present (harmless), 2=error
    ${If} $PathCheck == 2
        MessageBox MB_OK|MB_ICONEXCLAMATION "Warning: could not remove from PATH (EnVar error $PathCheck).$\nPlease remove '$INSTDIR' from your user PATH manually."
    ${EndIf}

    !insertmacro NotifyPathChange

    ; Delete uninstaller explicitly first — RMDir /r cannot remove locked files.
    ; The NSIS uninstall process shadow-copies itself so this is safe to call.
    Delete "$INSTDIR\uninstall.exe"

    ; /REBOOTOK schedules deletion on next reboot if any file is currently locked,
    ; rather than silently leaving the directory behind.
    RMDir /r /REBOOTOK "$INSTDIR"
    RMDir /r /REBOOTOK "$SMPROGRAMS\${APPNAME}"
    DeleteRegKey HKCU "${REG_KEY}"
SectionEnd
