# CalDavClient.ps1
#
# Shared CalDAV plumbing for vault-calendar POC scripts: auth header construction, a
# PROPFIND/REPORT request helper that follows iCloud's partition-host redirect manually
# (preserving method/body, which Invoke-WebRequest's built-in redirect handling would
# not for non-GET methods), and calendar discovery (RFC 4791 / RFC 6764 chain).
#
# Dot-source this file, then:
#   $AuthHeader = Get-CalDavAuthHeader -AppleId $AppleId -AppPassword $SecureAppPassword
#   $Calendars  = Get-CalDavCalendars -AuthHeader $AuthHeader   # -> DisplayName, Href, Components
#   $Result     = Invoke-CalDavRequest -Uri $Href -Method REPORT -Body $Xml -AuthHeader $AuthHeader -Depth 1
#   $Xml        = Get-CalDavResponseXml $Result

$Script:CalDavNs = @{
    d  = 'DAV:'
    c  = 'urn:ietf:params:xml:ns:caldav'
    cs = 'http://calendarserver.org/ns/'
}

function Get-CalDavAuthHeader {
    param(
        [Parameter(Mandatory)][string]$AppleId,
        [Parameter(Mandatory)][securestring]$AppPassword
    )
    $Plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($AppPassword))
    "Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($AppleId):$($Plain)"))
}

# Issues a PROPFIND/REPORT, following redirects manually (up to 5 hops) so the method
# and body are preserved — iCloud's initial response redirects caldav.icloud.com to a
# per-account partition host. Returns @{ Response; Uri } — Uri is the host that actually
# answered, needed to resolve relative hrefs in the response body (BaseResponse in PS7 is
# an HttpResponseMessage with no ResponseUri property, so it can't be read back off it).
function Invoke-CalDavRequest {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][ValidateSet('PROPFIND', 'REPORT')][string]$Method,
        [Parameter(Mandatory)][string]$Body,
        [Parameter(Mandatory)][string]$AuthHeader,
        [int]$Depth = 0
    )

    $CurrentUri = $Uri
    for ($hop = 0; $hop -le 5; $hop++) {
        $Headers = @{
            Authorization = $AuthHeader
            Depth         = "$Depth"
        }
        try {
            $Response = Invoke-WebRequest -Uri $CurrentUri -CustomMethod $Method -Headers $Headers `
                -Body $Body -ContentType 'application/xml; charset=utf-8' `
                -MaximumRedirection 0 -ErrorAction Stop
            return [PSCustomObject]@{ Response = $Response; Uri = [Uri]$CurrentUri }
        } catch {
            $WebResponse = $_.Exception.Response
            if ($null -eq $WebResponse) { throw }
            $StatusCode = [int]$WebResponse.StatusCode
            if ($StatusCode -in 301, 302, 307, 308) {
                $Location = $WebResponse.Headers.Location
                if (-not $Location) { throw "Redirect ($StatusCode) with no Location header from $CurrentUri" }
                $CurrentUri = if ($Location -is [Uri]) { $Location.AbsoluteUri } else { [string]$Location }
                Write-Host "  (redirected -> $CurrentUri)"
                continue
            }
            # 207 Multi-Status is success; anything else is a real failure.
            if ($StatusCode -eq 207 -and $WebResponse.Content) {
                return [PSCustomObject]@{ Response = $WebResponse; Uri = [Uri]$CurrentUri }
            }
            throw "CalDAV request failed: $StatusCode $($WebResponse.StatusDescription) ($CurrentUri)`n$($_.ErrorDetails.Message)"
        }
    }
    throw "Too many redirects resolving $Uri"
}

function Get-CalDavResponseXml {
    param([Parameter(Mandatory)]$Result)
    [xml]$Result.Response.Content
}

# Walks the discovery chain (current-user-principal -> calendar-home-set -> calendar
# list) and returns each calendar collection as @{ DisplayName; Href; Components }.
function Get-CalDavCalendars {
    param(
        [Parameter(Mandatory)][string]$AuthHeader
    )

    $Step1Body = @"
<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:current-user-principal />
  </d:prop>
</d:propfind>
"@
    $Step1 = Invoke-CalDavRequest -Uri "https://caldav.icloud.com/" -Method PROPFIND -Body $Step1Body -AuthHeader $AuthHeader -Depth 0
    $Step1Xml = Get-CalDavResponseXml $Step1
    $PrincipalHref = (Select-Xml -Xml $Step1Xml -Namespace $Script:CalDavNs -XPath '//d:current-user-principal/d:href').Node.InnerText
    if (-not $PrincipalHref) { throw "Could not find current-user-principal in response:`n$($Step1.Response.Content)" }
    $PrincipalUri = [Uri]::new($Step1.Uri, $PrincipalHref).AbsoluteUri

    $Step2Body = @"
<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop>
    <c:calendar-home-set />
  </d:prop>
</d:propfind>
"@
    $Step2 = Invoke-CalDavRequest -Uri $PrincipalUri -Method PROPFIND -Body $Step2Body -AuthHeader $AuthHeader -Depth 0
    $Step2Xml = Get-CalDavResponseXml $Step2
    $HomeSetHref = (Select-Xml -Xml $Step2Xml -Namespace $Script:CalDavNs -XPath '//c:calendar-home-set/d:href').Node.InnerText
    if (-not $HomeSetHref) { throw "Could not find calendar-home-set in response:`n$($Step2.Response.Content)" }
    $HomeSetUri = [Uri]::new($Step2.Uri, $HomeSetHref).AbsoluteUri

    $Step3Body = @"
<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">
  <d:prop>
    <d:displayname />
    <d:resourcetype />
    <c:supported-calendar-component-set />
    <cs:getctag />
  </d:prop>
</d:propfind>
"@
    $Step3 = Invoke-CalDavRequest -Uri $HomeSetUri -Method PROPFIND -Body $Step3Body -AuthHeader $AuthHeader -Depth 1
    $Step3Xml = Get-CalDavResponseXml $Step3

    $Calendars = @()
    foreach ($Resp in (Select-Xml -Xml $Step3Xml -Namespace $Script:CalDavNs -XPath '//d:response').Node) {
        $Href = (Select-Xml -Xml $Resp -Namespace $Script:CalDavNs -XPath 'd:href').Node.InnerText
        $IsCalendar = (Select-Xml -Xml $Resp -Namespace $Script:CalDavNs -XPath './/c:calendar' -ErrorAction SilentlyContinue)
        if (-not $IsCalendar) { continue }

        $DisplayName = (Select-Xml -Xml $Resp -Namespace $Script:CalDavNs -XPath './/d:displayname').Node.InnerText
        $Components = (Select-Xml -Xml $Resp -Namespace $Script:CalDavNs -XPath './/c:supported-calendar-component-set/c:comp').Node |
            ForEach-Object { $_.name }

        $Calendars += [PSCustomObject]@{
            DisplayName = $DisplayName
            Href        = [Uri]::new($Step3.Uri, $Href).AbsoluteUri
            Components  = $Components -join ', '
        }
    }
    $Calendars
}
