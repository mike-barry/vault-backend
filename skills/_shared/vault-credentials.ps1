# vault-credentials.ps1
#
# Thin P/Invoke wrapper around the Windows Credential Manager Win32 API
# (advapi32.dll: CredRead/CredWrite/CredFree). No external module dependency.
#
# Credentials are stored as CRED_TYPE_GENERIC with CRED_PERSIST_LOCAL_MACHINE, scoped to
# the current Windows user account and protected by DPAPI. Reads/writes are silent - no
# master password or unlock step - as long as the caller runs as the same Windows user
# who stored the credential, which is what makes this suitable for unattended/scheduled
# use (unlike Microsoft.PowerShell.SecretStore, which requires an interactive unlock by
# default).
#
# Windows Credential Manager targets are a single global per-user namespace, not scoped
# per-application - two skills that both pick Target "icloud" would silently overwrite
# each other's credential. Always prefix Target with the owning skill's name:
#   "<skill-name>:<purpose>"   e.g. "vault-calendar:icloud", "vault-transcript-fetch:omi"
#
# Dot-source this file (from a skill's scripts/ folder):
#   . (Join-Path $PSScriptRoot '..' '..' '_shared' 'vault-credentials.ps1')
# then use:
#   Set-StoredCredential -Target "vault-calendar:icloud" -UserName $u -Password $secureString
#   Get-StoredCredential -Target "vault-calendar:icloud"   # -> @{ UserName; Password (SecureString) } or $null
#   Remove-StoredCredential -Target "vault-calendar:icloud"

if (-not ("VaultCredManagerNative" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class VaultCredManagerNative {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CREDENTIAL {
        public int Flags;
        public int Type;
        public string TargetName;
        public string Comment;
        public long LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CredWrite(ref CREDENTIAL credential, uint flags);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CredDelete(string target, int type, int flags);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool CredFree(IntPtr credentialPtr);
}
"@
}

# CRED_TYPE_GENERIC
$Script:CredTypeGeneric = 1
# CRED_PERSIST_LOCAL_MACHINE - survives reboots/logins for this Windows user, this machine only.
$Script:CredPersistLocalMachine = 2

# Stores (or overwrites) a generic credential in Windows Credential Manager.
function Set-StoredCredential {
    param(
        # Arbitrary identifier for this credential, e.g. "vault-calendar:icloud".
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$UserName,
        [Parameter(Mandatory)][securestring]$Password
    )

    $Bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    try {
        $PlainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Bstr)
    }

    $BlobBytes = [Text.Encoding]::Unicode.GetBytes($PlainPassword)
    $BlobPtr = [Runtime.InteropServices.Marshal]::AllocHGlobal($BlobBytes.Length)
    try {
        [Runtime.InteropServices.Marshal]::Copy($BlobBytes, 0, $BlobPtr, $BlobBytes.Length)

        $Cred = New-Object VaultCredManagerNative+CREDENTIAL
        $Cred.Type = $Script:CredTypeGeneric
        $Cred.TargetName = $Target
        $Cred.CredentialBlobSize = $BlobBytes.Length
        $Cred.CredentialBlob = $BlobPtr
        $Cred.Persist = $Script:CredPersistLocalMachine
        $Cred.UserName = $UserName

        $Ok = [VaultCredManagerNative]::CredWrite([ref]$Cred, 0)
        if (-not $Ok) {
            $ErrCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "CredWrite failed for target '$Target' (Win32 error $ErrCode)"
        }
    } finally {
        [Runtime.InteropServices.Marshal]::FreeHGlobal($BlobPtr)
        [Array]::Clear($BlobBytes, 0, $BlobBytes.Length)
    }
}

# Retrieves a generic credential from Windows Credential Manager.
# Returns $null if no credential is stored under $Target.
function Get-StoredCredential {
    param(
        [Parameter(Mandatory)][string]$Target
    )

    $CredPtr = [IntPtr]::Zero
    $Ok = [VaultCredManagerNative]::CredRead($Target, $Script:CredTypeGeneric, 0, [ref]$CredPtr)
    if (-not $Ok) { return $null }

    try {
        $Cred = [Runtime.InteropServices.Marshal]::PtrToStructure($CredPtr, [type][VaultCredManagerNative+CREDENTIAL])

        $PasswordBytes = New-Object byte[] $Cred.CredentialBlobSize
        [Runtime.InteropServices.Marshal]::Copy($Cred.CredentialBlob, $PasswordBytes, 0, $Cred.CredentialBlobSize)
        $PlainPassword = [Text.Encoding]::Unicode.GetString($PasswordBytes)
        [Array]::Clear($PasswordBytes, 0, $PasswordBytes.Length)

        [PSCustomObject]@{
            UserName = $Cred.UserName
            Password = (ConvertTo-SecureString -String $PlainPassword -AsPlainText -Force)
        }
    } finally {
        # CredFree's bool return would otherwise leak into this function's output stream
        # and turn the single PSCustomObject return above into a 2-element array.
        [void][VaultCredManagerNative]::CredFree($CredPtr)
    }
}

# Deletes a stored credential. Returns $false (not an error) if none existed.
function Remove-StoredCredential {
    param(
        [Parameter(Mandatory)][string]$Target
    )
    [VaultCredManagerNative]::CredDelete($Target, $Script:CredTypeGeneric, 0)
}
