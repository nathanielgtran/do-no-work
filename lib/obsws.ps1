# Minimal obs-websocket v5 client. Runs Windows-side so it can reach OBS on loopback.
# Input:  env OBS_WS_PASSWORD, env OBS_WS_REQUESTS (JSON array of {requestType, requestData})
# Output: one JSON line per response {requestType, ok, code, comment, data}
# Exit:   0 all ok, 1 a request failed, 2 cannot connect/authenticate
$ErrorActionPreference = 'Stop'
$ct = [Threading.CancellationToken]::None
$utf8 = [Text.Encoding]::UTF8

function Send-Msg($ws, $obj) {
    $bytes = $utf8.GetBytes(($obj | ConvertTo-Json -Depth 10 -Compress))
    $ws.SendAsync([ArraySegment[byte]]$bytes, 'Text', $true, $ct).Wait()
}

function Receive-Msg($ws) {
    $buf = New-Object byte[] 65536
    $ms = New-Object IO.MemoryStream
    do {
        $task = $ws.ReceiveAsync([ArraySegment[byte]]$buf, $ct)
        $task.Wait()
        if ($task.Result.MessageType -eq 'Close') {
            throw "OBS closed the connection ($($ws.CloseStatus) $($ws.CloseStatusDescription))"
        }
        $ms.Write($buf, 0, $task.Result.Count)
    } while (-not $task.Result.EndOfMessage)
    return $utf8.GetString($ms.ToArray()) | ConvertFrom-Json
}

function Get-AuthString($password, $salt, $challenge) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $secret = [Convert]::ToBase64String($sha.ComputeHash($utf8.GetBytes($password + $salt)))
    return [Convert]::ToBase64String($sha.ComputeHash($utf8.GetBytes($secret + $challenge)))
}

function Connect-Obs($password) {
    $ws = New-Object Net.WebSockets.ClientWebSocket
    $ws.Options.AddSubProtocol('obswebsocket.json')
    $ws.ConnectAsync([Uri]'ws://127.0.0.1:4455', $ct).Wait()
    $hello = Receive-Msg $ws
    $identify = @{ rpcVersion = 1; eventSubscriptions = 0 }
    if ($hello.d.authentication) {
        $a = $hello.d.authentication
        $identify.authentication = Get-AuthString $password $a.salt $a.challenge
    }
    Send-Msg $ws @{ op = 1; d = $identify }
    $null = Receive-Msg $ws
    return $ws
}

try {
    $ws = Connect-Obs $env:OBS_WS_PASSWORD
} catch {
    [Console]::Error.WriteLine("cannot connect to OBS websocket: $($_.Exception.GetBaseException().Message)")
    exit 2
}

$failed = $false
foreach ($req in ($env:OBS_WS_REQUESTS | ConvertFrom-Json)) {
    $d = @{ requestType = $req.requestType; requestId = [guid]::NewGuid().ToString() }
    if ($req.requestData) { $d.requestData = $req.requestData }
    Send-Msg $ws @{ op = 6; d = $d }
    $resp = Receive-Msg $ws
    $out = @{
        requestType = $req.requestType
        ok          = [bool]$resp.d.requestStatus.result
        code        = $resp.d.requestStatus.code
        comment     = $resp.d.requestStatus.comment
        data        = $resp.d.responseData
    }
    Write-Output ($out | ConvertTo-Json -Depth 10 -Compress)
    if (-not $out.ok) { $failed = $true; break }
}
$ws.Dispose()
if ($failed) { exit 1 }
exit 0
