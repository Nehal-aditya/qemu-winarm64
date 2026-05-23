# installer.nsi
!include "LogicLib.nsh"

!define APPNAME "QEMU ARM64"
!define COMPANY "Custom Build Pipeline"
!define DESCRIPTION "Native QEMU System Emulator for Windows 11 ARM64"
!define VERSION "1.0.0"
!define REG_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}"

Name "${APPNAME}"
OutFile "qemu-user-setup.exe"

# Keeps the installer strictly in non-admin user mode
RequestExecutionLevel user

# Default install location (user-local, no admin needed)
InstallDir "$LOCALAPPDATA\Programs\qemu"

Page directory
Page instfiles

Section "Install"
    SetShellVarContext current
    SetOutPath "$INSTDIR"
    File /r "qemu-windows-arm64\*"

    # Start Menu shortcuts — both shipped emulator targets
    CreateDirectory "$SMPROGRAMS\${APPNAME}"
    CreateShortcut "$SMPROGRAMS\${APPNAME}\QEMU System AArch64.lnk" \
        "$INSTDIR\qemu-system-aarch64.exe" "" "$INSTDIR\qemu-system-aarch64.exe" 0
    CreateShortcut "$SMPROGRAMS\${APPNAME}\QEMU System x86_64.lnk" \
        "$INSTDIR\qemu-system-x86_64.exe" "" "$INSTDIR\qemu-system-x86_64.exe" 0

    # Write uninstall registry entries to HKCU (no admin required)
    WriteRegStr HKCU "${REG_KEY}" "DisplayName"     "${APPNAME}"
    WriteRegStr HKCU "${REG_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
    WriteRegStr HKCU "${REG_KEY}" "DisplayVersion"  "${VERSION}"
    WriteRegStr HKCU "${REG_KEY}" "Publisher"       "${COMPANY}"
    # FIX: store the actual install path so the uninstaller can find it
    # regardless of what drive/directory the user chose.
    WriteRegStr HKCU "${REG_KEY}" "InstallLocation" "$INSTDIR"

    # Add the install directory to the current user's PATH
    EnVar::SetHKCU
    EnVar::Check "PATH" "$INSTDIR"
    Pop $0
    ${If} $0 != 0
        EnVar::AddValue "PATH" "$INSTDIR"
    ${EndIf}

    WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

Section "Uninstall"
    SetShellVarContext current

    # FIX: Read the stored install location back from the registry so
    # $INSTDIR is correct even when the user installed to a custom path/drive.
    ReadRegStr $INSTDIR HKCU "${REG_KEY}" "InstallLocation"

    # Remove from PATH using the exact stored path
    EnVar::SetHKCU
    EnVar::DeleteValue "PATH" "$INSTDIR"

    RMDir /r "$INSTDIR"
    RMDir /r "$SMPROGRAMS\${APPNAME}"
    DeleteRegKey HKCU "${REG_KEY}"
SectionEnd
