function Sh3ller{
	#Sh3ller [https://github.com/Leo4j/Sh3ller]
    param([Parameter(Mandatory = $true)][Alias("Port")][string]$p)

    $Failure = $False
    netstat -na | Select-String LISTENING | ForEach-Object {
        if (($_.ToString().Split(":")[1].Split(" ")[0]) -eq $p) {
            Write-Output ("The selected port " + $p + " is already in use.")
            $Failure = $True
        }
    }
    if ($Failure){return}
	
	Start-Sleep -Milliseconds 200
	$Host.UI.RawUI.FlushInputBuffer()

    $global:Connections        = @{}
    $global:ConnectionCounter  = 0
    $global:ListenerActive     = $true
    $global:counter            = 0
    $global:datacounter        = 0
    $global:menuchecker        = $True
    $global:NewConnQueue       = [System.Collections.Generic.Queue[int]]::new()

    function Setup_TCP_Listener {
        param($FuncSetupVars)
        $p = $FuncSetupVars
        if ($global:Verbose) { $Verbose = $True }
        $FuncVars = @{}
        $Socket = New-Object System.Net.Sockets.TcpListener $p
        $Socket.Start()
        $FuncVars["Socket"] = $Socket
        return $FuncVars
    }

    function Accept_Connections {
        param($ListenerVars)
        while ($ListenerVars["Socket"].Pending()) {
            $Client        = $ListenerVars["Socket"].AcceptTcpClient()
            $Stream        = $Client.GetStream()
            $BufferSize    = $Client.ReceiveBufferSize
            $ConnectionId  = $global:ConnectionCounter
            $global:ConnectionCounter++
            $buf           = New-Object System.Byte[] $BufferSize
            $Connection = @{
                "Client"                    = $Client
                "Stream"                    = $Stream
                "BufferSize"                = $BufferSize
                "StreamDestinationBuffer"   = $buf
                "Encoding"                  = (New-Object System.Text.AsciiEncoding)
                "StreamBytesRead"           = 1
            }
            $Connection["StreamReadOperation"] = $Stream.BeginRead($Connection["StreamDestinationBuffer"], 0, $BufferSize, $null, $null)
            $global:Connections[$ConnectionId] = $Connection
            $global:NewConnQueue.Enqueue([int]$ConnectionId)
        }
    }

    function Drain-NewConnectionNotifications {
        param([switch]$Silent, [switch]$Duck)
        $any = $false
        while ($global:NewConnQueue.Count -gt 0) {
            $id = $global:NewConnQueue.Dequeue()
            if (-not $global:Connections.ContainsKey($id)) { continue }
            $c = $global:Connections[$id]
            if (-not $Silent) {
                $ip   = $c.Client.Client.RemoteEndPoint.Address
                $port = $c.Client.Client.RemoteEndPoint.Port
				Write-Host (" [+] New connection [{0}] {1}:{2}" -f $id, $ip, $port) -Foreground Yellow
            }
            $global:counter = 0
            $global:datacounter = 0
            $any = $true
        }
        if (-not $Duck) { return $any }
    }

    function ReadData_TCP {
        param($Connection)
        $Data = $null
        if ($Connection["StreamBytesRead"] -eq 0) {return $null, $Connection}
        try {
            $stream = $Connection["Stream"]
            $client = $Connection["Client"]
            if ($Connection["StreamReadOperation"].IsCompleted) {
                $StreamBytesRead = $stream.EndRead($Connection["StreamReadOperation"])
                if ($StreamBytesRead -eq 0) {
                    $Connection["StreamBytesRead"] = 0
                    return $null, $Connection
                }
                $Data = $Connection["StreamDestinationBuffer"][0..($StreamBytesRead - 1)]
                $Connection["StreamReadOperation"] = $stream.BeginRead($Connection["StreamDestinationBuffer"], 0, $Connection["BufferSize"], $null, $null)
            } else {
                if (-not $client.Client.Poll(0, [System.Net.Sockets.SelectMode]::SelectRead) -or $client.Client.Available -ne 0) {} 
				else {
                    $Connection["StreamBytesRead"] = 0
                    return $null, $Connection
                }
            }
        } catch {
            $Connection["StreamBytesRead"] = 0
            return $null, $Connection
        }
        return $Data, $Connection
    }

    function WriteData_TCP {
        param($Data, $Connection)
		Start-Sleep -Milliseconds 200
		$Host.UI.RawUI.FlushInputBuffer()
        try {
            $Connection["Stream"].Write($Data, 0, $Data.Length)
        } catch {
            $Connection["StreamBytesRead"] = 0
        }
        return $Connection
    }

    function Close_Connection {
        param($Connection)
        try { $Connection["Stream"].Close() } catch {}
        try { $Connection["Client"].Close() } catch {}
    }

    function Setup_Console {
        $FuncVars = @{}
        $FuncVars["Encoding"] = New-Object System.Text.AsciiEncoding
        return $FuncVars
    }

    function ReadData_Temp {
        param($FuncVars)
        $global:counter = 1
        $Data  = $FuncVars["Encoding"].GetBytes("`n")
        return $Data, $FuncVars
    }

    function ReadData_Console {
        param($FuncVars)
        $Data = $null
        if ($Host.UI.RawUI.KeyAvailable) {
            $input = Read-Host
            if ($input -ne $null) {
                $Data = $FuncVars["Encoding"].GetBytes($input + "`n")
            }
            Write-Host $(PrintDate)
        }
        return $Data, $FuncVars
    }

    function WriteData_Console {
        param($Data, $FuncVars)
        Write-Host -NoNewline $FuncVars["Encoding"].GetString($Data)
        return $FuncVars
    }

    function Show_Menu {
		Start-Sleep -Milliseconds 200
		$Host.UI.RawUI.FlushInputBuffer()
        Write-Host ""
		Write-Host " Sh3ller [https://github.com/Leo4j/Sh3ller]" -ForegroundColor DarkCyan
		Write-Host ""
        Write-Host " Active Connections:" -Foreground cyan
        Write-Host ""

        if ($global:Connections.Count -eq 0) {
            Write-Host " No active connections."
            Write-Host ""
            Write-Host -NoNewline " Select a connection ID, or type 'kill <id>' or 'exit': "
            return
        }
        foreach ($kv in $global:Connections.GetEnumerator() | Sort-Object Name) {
            $id   = $kv.Name
            $conn = $kv.Value
            $ip   = $conn.Client.Client.RemoteEndPoint.Address
            $port = $conn.Client.Client.RemoteEndPoint.Port
            Write-Host (" [{0}] {1}:{2}" -f $id, $ip, $port) -Foreground Yellow
        }
        Write-Host ""
        Write-Host -NoNewline " Select a connection ID, or type 'kill <id>' or 'exit': "
    }

    function PrintDate {
        $d = Get-Date
        "{0:dd MMMM yyyy HH:mm:ss} ({1})" -f $d, $(if ([TimeZoneInfo]::Local.IsDaylightSavingTime($d)) { 'BST' } else { 'GMT' })
    }

    function CheckClosed {
        param([switch]$NoOps)
        $closedConnections = @()
        $global:Connections.GetEnumerator() | ForEach-Object {
            $conn = $_.Value
            if ($conn["StreamBytesRead"] -eq 0) {
                $closedConnections += $_.Name
            }
        }
        if ($NoOps -and $closedConnections.Count -ne 0) { $global:closetrigger = $False; break }
        $closedConnections | ForEach-Object {
            Close_Connection $global:Connections[$_]
            $global:Connections.Remove($_)
            Write-Host " [-] Connection $_ closed by remote host." -Foreground red
        }
    }

    function MenuCheckClosed {
        param(
            [switch]$Silent,
            [switch]$Reset,
            [switch]$Duck,
            [int]$ExcludeConnection = -1
        )
        $closedConnections = @()
        $connectionKeys = $global:Connections.Keys | ForEach-Object { $_ }
        foreach ($connId in $connectionKeys) {
            if ($connId -eq $ExcludeConnection) { continue }
            $conn = $global:Connections[$connId]

            $null, $updatedConn = ReadData_TCP $conn
            $global:Connections[$connId] = $updatedConn

            if ($updatedConn["StreamBytesRead"] -eq 0) {
                $closedConnections += $connId
            }
        }

        if ($closedConnections.Count -gt 0 -and $Reset) {
            $global:counter = 0
            $global:datacounter = 0
        }

        foreach ($connId in $closedConnections) {
            Close_Connection $global:Connections[$connId]
            $global:Connections.Remove($connId)
            if (-not $Silent) {
                if ($Reset) {
                    Write-Host " [-] Connection $connId closed by remote host." -ForegroundColor Red
                } else {
                    Write-Host ""
                    Write-Host " [-] Connection $connId closed by remote host." -ForegroundColor Red
                }
            }
        }
        if (-not $Duck) { return $closedConnections.Count }
    }

    function Cleaning {
        param($ListenerVars)
        $global:Connections.GetEnumerator() | ForEach-Object {Close_Connection $_.Value}
        $global:Connections.Clear()
        try { if ($ListenerVars -and $ListenerVars["Socket"]) { $ListenerVars["Socket"].Stop() } } catch {}
    }

    function Wait-ForUserCommand {
        param($ListenerVars)

        while (-not $Host.UI.RawUI.KeyAvailable) {
            $changed = $false
            Accept_Connections $ListenerVars
            if (Drain-NewConnectionNotifications) { $changed = $true }
            if ((MenuCheckClosed -Reset) -gt 0) { $changed = $true }
            if ($changed) { Show_Menu }
            Start-Sleep -Milliseconds 150
        }
    }

    function Main {
        param($Stream1SetupVars)
        $Output = $null
        try {
            $ListenerVars = Setup_TCP_Listener $Stream1SetupVars
            $ConsoleVars  = Setup_Console

            while ($global:ListenerActive) {
                Accept_Connections $ListenerVars
                Drain-NewConnectionNotifications -Silent -Duck
                if ($global:menuchecker) { MenuCheckClosed -Duck } else { $global:menuchecker = $True; MenuCheckClosed -Silent -Duck }
                Show_Menu

                Wait-ForUserCommand $ListenerVars
                $choice = Read-Host

                if ($choice -eq "") {
                    # no-op
                }
                elseif ($choice -eq "exit") {
					Write-Host ""
                    $global:ListenerActive = $false
                    break
                }
                elseif ($choice -match '^kill\s+(\d+)$') {
                    $connId = [int]$matches[1]
                    if ($global:Connections.ContainsKey([int]$connId)) {
                        Close_Connection $global:Connections[[int]$connId]
                        $global:Connections.Remove([int]$connId)
                        Write-Host ""
                        Write-Host " [-] Connection $connId closed." -Foreground red
                    } else {
						Write-Host ""
                        Write-Host " [-] Invalid connection ID: $connId" -Foreground red
                    }
                }
				elseif ($choice -eq "kill all") {
					$ids = @($global:Connections.Keys | ForEach-Object { [int]$_ })

					if ($ids.Count -eq 0) {
						Write-Host "[-] No connections to close." -ForegroundColor Yellow
						continue
					}

					foreach ($id in $ids) {
						try {
							if ($global:Connections.ContainsKey($id)) {
								Close_Connection $global:Connections[$id]
								$global:Connections.Remove($id)
								Write-Host (" [-] Connection {0} closed." -f $id) -ForegroundColor Red
							}
						} catch {}
					}
					$global:counter = 0
					$global:datacounter = 0
					$global:menuchecker = $False
					continue
				}
                elseif ($choice -match '^\d+$') {
					Start-Sleep -Milliseconds 200
					$Host.UI.RawUI.FlushInputBuffer()
                    $global:closetrigger = $True
                    $connId = [int]$choice
                    if ($global:Connections.ContainsKey([int]$connId)) {
                        Write-Host ""
                        Write-Host " Entering shell for connection $connId. Type 'menu' to return to menu.`n"
                        $Connection = $global:Connections[[int]$connId]

                        while ($global:ListenerActive -and $global:closetrigger) {
							$Data, $Connection = ReadData_TCP $Connection

                            if ($Connection["StreamBytesRead"] -eq 0) {
                                Write-Host " [-] Connection $connId closed by remote host." -ForegroundColor Red
                                try { Close_Connection $Connection } catch {}
                                if ($global:Connections.ContainsKey([int]$connId)) {
                                    $global:Connections.Remove([int]$connId)
                                }
                                $global:counter = 0
                                $global:datacounter = 0
                                break
                            }

                            if ($Data -ne $null -and $global:counter -ne 0) {
                                $ConsoleVars = WriteData_Console $Data $ConsoleVars
                                $global:datacounter++
                            }
                            if ($global:counter -eq 0) { $Data, $ConsoleVars = ReadData_Temp $ConsoleVars }
                            else { $Data, $ConsoleVars = ReadData_Console $ConsoleVars }

                            if ($Data -ne $null) {
                                $cmd = $ConsoleVars["Encoding"].GetString($Data).Trim()
                                if ($cmd -in @("menu", "exit")) {
                                    $global:counter = 0
                                    $global:datacounter = 0
                                    break
                                }
                                elseif ($cmd -eq "kill") {
                                    Close_Connection $global:Connections[[int]$connId]
                                    $global:Connections.Remove([int]$connId)
                                    $global:counter = 0
                                    $global:datacounter = 0
                                    $global:menuchecker = $False
                                    Write-Host ""
                                    Write-Host " [-] Connection $connId closed." -ForegroundColor Red
                                    break
                                }
                                $Connection = WriteData_TCP $Data $Connection
                            }
                            Accept_Connections $ListenerVars
                            Drain-NewConnectionNotifications -Duck
                            MenuCheckClosed -ExcludeConnection $connId -Reset -Duck
                            Start-Sleep -Milliseconds 120
                        }

                        if ($global:Connections.ContainsKey([int]$connId)) {$global:Connections[[int]$connId] = $Connection}
                    } else {
                        Write-Host ""
                        Write-Host " [-] Invalid connection ID: $connId" -Foreground red
                    }
                }
                CheckClosed
                Start-Sleep -Milliseconds 100
            }
        }
        finally {Cleaning $ListenerVars}
    }
    Main @($p)
}
