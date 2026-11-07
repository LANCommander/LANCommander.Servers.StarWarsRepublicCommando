#Requires -Modules Logging

# Create the server ini (RC_INI, default System/Server.ini) from the game's System.ini on first
# start, then write the RC_* settings and the map rotation into it. It's created through the
# merged view, so it lands in Overlay/ and can be edited there; keys without an RC_* setting are
# never touched. UCC reads only this file: the Save/ copies the game client layers over System.ini
# don't apply to it.

$system   = Join-Path $Env:SERVER_ROOT 'System'
$template = Join-Path $system 'System.ini'
$ini      = Join-Path $system $Env:RC_INI

if (-not (Test-Path -Path $ini)) {
    if (-not (Test-Path -Path $template)) {
        Write-Log -Level Error "$template not found; skipping server configuration"
        return
    }

    Copy-Item -Path $template -Destination $ini
    Write-Log "Created $ini from System.ini"
}

$text    = [System.IO.File]::ReadAllText($ini)
$newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
$lines   = [System.Collections.Generic.List[string]]::new([string[]]($text -split "\r?\n"))

function Get-SectionRange([string] $Section) {
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -ieq "[$Section]") { $start = $i; break }
    }
    if ($start -lt 0) { return $null }

    $end = $start + 1
    while ($end -lt $lines.Count -and -not $lines[$end].StartsWith('[')) { $end++ }
    return @($start, $end)
}

# Insert a line after the section's last non-blank line, creating the section if needed
function Add-IniLine([string] $Section, [string] $Line) {
    $range = Get-SectionRange $Section
    if (-not $range) {
        if ($lines.Count -and $lines[$lines.Count - 1] -ne '') { $lines.Add('') }
        $lines.Add("[$Section]")
        $lines.Add($Line)
        return
    }

    $start, $end = $range
    $at = $end
    while ($at -gt $start + 1 -and [string]::IsNullOrWhiteSpace($lines[$at - 1])) { $at-- }
    $lines.Insert($at, $Line)
}

# Set Key=Value in [Section], replacing the first existing Key= line or appending to the section
function Set-IniValue([string] $Section, [string] $Key, [string] $Value) {
    $range = Get-SectionRange $Section
    if ($range) {
        for ($i = $range[0] + 1; $i -lt $range[1]; $i++) {
            if ($lines[$i].StartsWith("$Key=", [System.StringComparison]::OrdinalIgnoreCase)) {
                $lines[$i] = "$Key=$Value"
                return
            }
        }
    }
    Add-IniLine $Section "$Key=$Value"
}

# Remove every Key= and Key+= line from [Section]
function Remove-IniKey([string] $Section, [string] $Key) {
    $range = Get-SectionRange $Section
    if (-not $range) { return }
    for ($i = $range[1] - 1; $i -gt $range[0]; $i--) {
        if ($lines[$i].StartsWith("$Key=", [System.StringComparison]::OrdinalIgnoreCase) -or
            $lines[$i].StartsWith("$Key+=", [System.StringComparison]::OrdinalIgnoreCase)) {
            $lines.RemoveAt($i)
        }
    }
}

function Test-True([string] $Value) { return $Value -in @('true', '1', 'yes') }
function ConvertTo-IniBool([string] $Value) {
    if (-not $Value) { return '' }
    if (Test-True $Value) { return 'True' } else { return 'False' }
}

# Game types: short names (same table as the rc-server launcher) and each class's map list
# (MapListType). TDGame, CTFGame and ASGame are team games.
$gameTypes = [ordered]@{
    'MPGame.DMGame'  = @{ MapList = 'MPGame.MapListDeathMatch';     Team = $false; Names = @('deathmatch', 'dm') }
    'MPGame.TDGame'  = @{ MapList = 'MPGame.MapListTeamDeathMatch'; Team = $true;  Names = @('teamdeathmatch', 'tdm', 'td', 'team') }
    'MPGame.CTFGame' = @{ MapList = 'MPGame.MapListCaptureTheFlag'; Team = $true;  Names = @('capturetheflag', 'ctf') }
    'MPGame.ASGame'  = @{ MapList = 'MPGame.MapListAssault';        Team = $true;  Names = @('assault', 'as') }
}

function Resolve-GameType([string] $Name) {
    foreach ($class in $gameTypes.Keys) {
        if ($Name -ieq $class -or $gameTypes[$class].Names -contains $Name.ToLowerInvariant()) { return $class }
    }
    return $Name
}

$gameType = Resolve-GameType $(if ($Env:RC_GAME_TYPE) { $Env:RC_GAME_TYPE } else { 'deathmatch' })
$known    = $gameTypes.Contains($gameType)
$isTeam   = $known -and $gameTypes[$gameType].Team

# GoalScore and TimeLimit are per class, so they go to the class being started; RoundTime,
# NumRounds and FriendlyFireScale only exist in the team games. bBalanceTeams is globalconfig in
# TDGame, so every team game reads it from there.
$settings = @(
    @('URL',                         'Port',          $Env:RC_PORT),
    @('Engine.GameReplicationInfo',  'ServerName',    $Env:RC_SERVER_NAME),
    @('Engine.GameReplicationInfo',  'ShortName',     $Env:RC_SHORT_NAME),
    @('Engine.GameReplicationInfo',  'AdminName',     $Env:RC_ADMIN_NAME),
    @('Engine.GameReplicationInfo',  'AdminEmail',    $Env:RC_ADMIN_EMAIL),
    @('Engine.GameReplicationInfo',  'MOTDLine1',     $Env:RC_MOTD),
    @('Engine.GameInfo',             'MaxPlayers',    $Env:RC_MAX_PLAYERS),
    @('Engine.GameInfo',             'MaxSpectators', $Env:RC_MAX_SPECTATORS),
    @('Engine.AccessControl',        'GamePassword',  $Env:RC_GAME_PASSWORD),
    @('Engine.AccessControl',        'AdminPassword', $Env:RC_ADMIN_PASSWORD),
    @($gameType,                     'GoalScore',     $Env:RC_GOAL_SCORE),
    @($gameType,                     'TimeLimit',     $Env:RC_TIME_LIMIT),
    @('MPGame.TDGame',               'bBalanceTeams', (ConvertTo-IniBool $Env:RC_BALANCE_TEAMS))
)

if ($isTeam -or -not $known) {
    $settings += , @($gameType, 'FriendlyFireScale', $Env:RC_FRIENDLY_FIRE_SCALE)
    $settings += , @($gameType, 'RoundTime',         $Env:RC_ROUND_TIME)
    $settings += , @($gameType, 'NumRounds',         $Env:RC_NUM_ROUNDS)
}

foreach ($s in $settings) {
    if ($s[2]) { Set-IniValue $s[0] $s[1] $s[2] }
}

# Map rotation: the game type's map list, one Maps= line per entry. An entry may carry URL
# options (DM_Hangar?Game=MPGame.TDGame?GoalScore=40), as in the stock MapListMixedDeathMatch
# example. With an empty list the game picks the next map with the same prefix.
if ($Env:RC_MAPS) {
    $mapList = if ($known) { $gameTypes[$gameType].MapList } else { 'MPGame.MapListDeathMatch' }

    $available = [ordered]@{}
    Get-ChildItem -Path (Join-Path $Env:SERVER_ROOT 'Maps') -Filter '*.ctm' -File -ErrorAction SilentlyContinue |
        ForEach-Object { $available[$_.BaseName.ToLowerInvariant()] = $_.BaseName }

    $rotation = @()
    foreach ($entry in @($Env:RC_MAPS -split '[,;\s]+' | Where-Object { $_ })) {
        $map, $options = $entry -split '\?', 2
        $map = $map -replace '\.ctm$', ''
        if ($available.Count -and -not $available.Contains($map.ToLowerInvariant())) {
            Write-Log -Level Warning "Map $map is not installed; left out of the rotation"
            continue
        }
        if ($available.Count) { $map = $available[$map.ToLowerInvariant()] }

        $rotation += $(if ($options) { "${map}?$options" } else { $map })
    }

    Remove-IniKey $mapList 'Maps'
    Remove-IniKey $mapList 'MapNum'
    for ($i = 0; $i -lt $rotation.Count; $i++) {
        Add-IniLine $mapList $(if ($i -eq 0) { "Maps=$($rotation[$i])" } else { "Maps+=$($rotation[$i])" })
    }

    # With MapNum=0 the game doesn't look the current map up in the list and goes to Maps[1] next,
    # so start the server on the rotation's first map (RC_MAP). The game saves MapNum back here on
    # every map change; it is reset on each start.
    Set-IniValue $mapList 'MapNum' '0'

    Write-Log "Map rotation ($mapList): $($rotation -join ', ')"
}

# LAN only by default. AdvertiseServer=2 also reports to the master server SWRCFix's
# GameSpyMgr.dll points at.
Set-IniValue 'IpDrv.MasterServerUplink' 'AdvertiseServer' $(if (Test-True $Env:RC_MASTER_SERVER_UPLINK) { '2' } else { '1' })

[System.IO.File]::WriteAllText($ini, ($lines -join $newline))
chown "$($Env:UID):$($Env:GID)" $ini

Write-Log "Applied RC_* settings to $ini"
