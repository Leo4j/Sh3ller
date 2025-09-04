# Sh3ller
Sh3ller is a lightweight C2 framework in its simplest form.

It’s built for one job only: catching shells and letting you manage them. Nothing more.

Sh3ller is always listening for incoming connections.

How you deliver your payload and how you bypass the firewall is entirely up to you.

## Features
- Lightweight, no dependencies beyond PowerShell
- Always listening for incoming connections
- Manage multiple shells at once

## Available Commands
| Command   | Description                          |
|-----------|--------------------------------------|
| `exit`           | Quit Sh3ller |
| `kill <id>`      | Close a specific session |
| `kill all`       | Close all active sessions |
| `<id>`           | Interact with a specific session |
| `menu or exit`   | Return to the main menu from a shell |

## Example of accepted TCP Rev Shell Payloads

- netcat
- powercat
- powershell reverse shells
- msfvenom’s `windows/x64/shell_reverse_tcp`
- custom tcp rev shell

## Load in memory and run

```
iex(new-object net.webclient).downloadstring('https://raw.githubusercontent.com/Leo4j/Sh3ller/main/Sh3ller.ps1')
```
```
Sh3ller 8080
```
