# installer.nsi
!define APPNAME "QEMU ARM64"
!define COMPANY "Custom Build Pipeline"
!define DESCRIPTION "Native QEMU System Emulator for Windows 11 ARM64"
!define VERSION "1.0.0"

Name "${APPNAME}"
OutFile "qemu-user-setup.exe"

# Keeps the installer strictly in non-admin user mode
RequestExecutionLevel user

# Default fallback location if the user clicks Next
InstallDir "$LOCALAPPDATA\Programs\qemu"

Page directory
Page instfiles

Section "Install"
    # Set context to current user so shortcuts don't go to protected Admin zones
    SetShellVarContext current
    
    # $INSTDIR automatically shifts to whatever path/drive the user picks
    SetOutPath "$INSTDIR"
    File /r "qemu-windows-arm64\*"
    
    # Create user-scoped Start Menu Shortcuts pointing to the custom location
    CreateDirectory "$SMPROGRAMS\${APPNAME}"
    CreateShortcut "$SMPROGRAMS\${APPNAME}\QEMU System AArch64.lnk" "$INSTDIR\qemu-system-aarch64.exe" "" "$INSTDIR\qemu-system-aarch64.exe" 0
    
    # Write registry tracks to the Current User (HKCU) hive
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "DisplayName" "${APPNAME}"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "UninstallString" '"$INSTDIR\uninstall.exe"'
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "DisplayVersion" "${VERSION}"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "Publisher" "${COMPANY}"

    # === DYNAMIC USER PATH UPDATER ===
    EnVar::SetHKCU
    # Check and add the custom directory, no matter what drive it is on
    EnVar::Check "PATH" "$INSTDIR"
    Pop $0
    ${If} $0 != 0
        EnVar::AddValue "PATH" "$INSTDIR"
    ${EndIf}

    # Generate the uninstaller inside the target folder
    WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

Section "Uninstall"
    SetShellVarContext current
    
    # === DYNAMIC USER PATH REMOVAL ===
    # Reads the exact custom directory location to clean up the PATH
    EnVar::SetHKCU
    EnVar::DeleteValue "PATH" "$INSTDIR"

    # Clear out the target folder and shortcuts
    RMDir /r "$INSTDIR"
    RMDir /r "$SMPROGRAMS\${APPNAME}"
    DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}"
SectionEnd