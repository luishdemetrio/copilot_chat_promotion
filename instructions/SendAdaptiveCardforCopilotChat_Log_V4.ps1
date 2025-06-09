# Requires PowerShell 7.0 or later for ForEach-Object -Parallel
# Requires the ImportExcel, Microsoft.Graph.Teams, and Microsoft.Graph.Authentication modules.

# --- Required Modules ---
Import-Module ImportExcel -ErrorAction Stop
Import-Module Microsoft.Graph.Teams -ErrorAction Stop
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

# --- Authentication ---
# Ensure you are connected to Microsoft Graph with appropriate scopes
$scopes = @("Chat.ReadWrite", "User.Read")
try {
    Connect-MgGraph -Scopes $scopes -ErrorAction Stop
    $myUserAccount = (Get-MgContext).Account
    $tenantId = (Get-MgContext).TenantId
    Write-Host "Successfully connected to Microsoft Graph." -ForegroundColor Green
} catch {
    Write-Error "Failed to connect to Microsoft Graph. Please ensure you have the necessary modules and permissions. Error: $($_.Exception.Message)"
    exit
}


# --- Input Data ---
# Input Excel file containing UPNs
$excelFilePath = "C:\Users\luisdem\Downloads\SendPromotion\Users.xlsx"
if (-not (Test-Path $excelFilePath)) {
    Write-Error "Input Excel file not found at: $excelFilePath"
    exit
}
try {
    $upns = Import-Excel -Path $excelFilePath | Select-Object -ExpandProperty UPN
    if (-not $upns) {
        Write-Warning "No UPNs found in the Excel file."
        exit
    }
    Write-Host "Successfully loaded UPNs from Excel file." -ForegroundColor Green
} catch {
    Write-Error "Failed to import data from Excel file. Error: $($_.Exception.Message)"
    exit
}


# --- Output Log File Setup ---
# Generate timestamped log file name
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "C:\Users\luisdem\Downloads\SendPromotion\CopilotMessageLog_$timestamp.csv"

# Create the log file with headers if it doesn't exist
# This will be done once before parallel processing
if (-not (Test-Path (Split-Path $logFile -Parent))) {
    New-Item -Path (Split-Path $logFile -Parent) -ItemType Directory -Force | Out-Null
}
"Timestamp,UPN,Status,Message" | Out-File -FilePath $logFile -Encoding UTF8

# --- Adaptive Card Setup ---
# Path to the Adaptive Card JSON file
$adaptiveCardPath = "C:\Users\luisdem\Downloads\SendPromotion\adaptivaCardActions.JSON" # Ensure this path is correct
if (-not (Test-Path $adaptiveCardPath)) {
    Write-Error "Adaptive Card JSON file not found at: $adaptiveCardPath"
    exit
}
try {
    $adaptiveCardJson = Get-Content -Path $adaptiveCardPath -Raw -Encoding UTF8
    # Optional: Replace placeholder in Adaptive Card JSON if needed
    # $adaptiveCardJson = $adaptiveCardJson -replace '\$tenantId', $tenantId
    Write-Host "Successfully loaded Adaptive Card JSON." -ForegroundColor Green
} catch {
    Write-Error "Failed to load Adaptive Card JSON file. Error: $($_.Exception.Message)"
    exit
}


# --- Retry Settings ---
$retryLimit = 3

# --- Thread-Safe Log Collection ---
# Create a thread-safe collection to store log messages from concurrent threads
$LogMessages = New-Object -TypeName System.Collections.Concurrent.ConcurrentBag[string]

# --- Parallel Processing ---

Write-Host "Starting parallel processing for $($upns.Count) users..." -ForegroundColor Yellow

$timeTaken = (Measure-Command {
    $upns | ForEach-Object -Parallel {
        # Access variables from parent scope using $using:
        $currentUserUPN = $_
        $threadRetryLimit = $using:retryLimit
        $threadMyUserAccount = $using:myUserAccount
        $threadAdaptiveCardJson = $using:adaptiveCardJson
        $threadLogBag = $using:LogMessages # Local variable to add logs to the ConcurrentBag

        $retries = 0
        while ($retries -lt $threadRetryLimit) {
            try {
                Write-Host "[$currentThreadId] Sending to $currentUserUPN..." -ForegroundColor Cyan

                # Create chat
                $params = @{
                    chatType = "oneOnOne"
                    members = @(
                        @{
                            "@odata.type" = "#microsoft.graph.aadUserConversationMember"
                            roles = @("owner")
                            "user@odata.bind" = "https://graph.microsoft.com/v1.0/users('$currentUserUPN')"
                        },
                        @{
                            "@odata.type" = "#microsoft.graph.aadUserConversationMember"
                            roles = @("owner")
                            "user@odata.bind" = "https://graph.microsoft.com/v1.0/users('$threadMyUserAccount')"
                        }
                    )
                }

                # Using -ErrorAction Stop to catch specific errors
                $chat = New-MgChat -BodyParameter $params -ErrorAction Stop
                $chatId = $chat.Id

                if (-not $chatId) {
                     # This case should ideally be caught by -ErrorAction Stop, but added as a safeguard
                    throw "Chat creation failed or returned no ID for $currentUserUPN"
                }

                $attachmentId = [guid]::NewGuid().ToString()

                # Message body
                $body = @{
                    contentType = "html"
                    content = "<attachment id='$attachmentId'></attachment>"
                }

                # Attachment
                $attachment = @{
                    id = $attachmentId
                    contentType = "application/vnd.microsoft.card.adaptive"
                    content = $threadAdaptiveCardJson
                }

                # Send message
                # Using -ErrorAction Stop to catch specific errors during message sending
                New-MgChatMessage -ChatId $chatId -Body $body -Attachments @($attachment) -ErrorAction Stop

                # Log success to the ConcurrentBag
                $logEntry = "$((Get-Date).ToString('u')),$currentUserUPN,Success,Message sent"
                $threadLogBag.Add($logEntry)
                Write-Host "[$currentThreadId] Message sent to $currentUserUPN" -ForegroundColor Green

                # Break out of the retry loop on success
                break

            } catch {
                $retries++
                $retryAfter = 0
                $errorMessage = $_.Exception.Message

                # Attempt to get Retry-After header if available
                if ($_.Exception.Response -and $_.Exception.Response.Headers["Retry-After"]) {
                    $retryAfter = [int]$_.Exception.Response.Headers["Retry-After"]
                    $errorMessage += " (Retry-After: $retryAfter seconds)"
                } else {
                    # Exponential backoff with jitter
                    $retryAfter = [math]::Pow(2, $retries) + (Get-Random -Minimum 1 -Maximum 3)
                }

                if ($retries -eq $threadRetryLimit) {
                    # Log final error to the ConcurrentBag after max retries
                    $logEntry = "$((Get-Date).ToString('u')),$currentUserUPN,Error,$errorMessage"
                    $threadLogBag.Add($logEntry)
                    Write-Host "[$currentThreadId] Failed to send to $currentUserUPN after $threadRetryLimit retries - $($errorMessage)" -ForegroundColor Red
                } else {
                    # Log retry attempt to the ConcurrentBag
                    $logEntry = "$((Get-Date).ToString('u')),$currentUserUPN,Retry $retries,Waiting $retryAfter seconds - $($errorMessage)"
                    $threadLogBag.Add($logEntry)
                    Write-Host "[$currentThreadId] Retrying to send to $currentUserUPN in $retryAfter seconds (Attempt $retries/$threadRetryLimit)..." -ForegroundColor Yellow
                    Start-Sleep -Seconds $retryAfter
                }
            }
        }
    } -ThrottleLimit 5 # Adjust ThrottleLimit as needed
}).TotalSeconds # Use TotalSeconds for potentially longer operations

Write-Host "Parallel processing finished." -ForegroundColor Yellow
Write-Host "Total Time Taken: $($timeTaken.ToString('N2')) seconds" -ForegroundColor Yellow


# --- Write Collected Logs to File ---
Write-Host "Writing collected logs to file: $logFile" -ForegroundColor Yellow

# Write all collected log messages from the ConcurrentBag to the log file
# Append to the file that was created with headers earlier
$LogMessages | Add-Content -Path $logFile -Encoding UTF8

Write-Host "Log file updated successfully with collected messages." -ForegroundColor Green

# --- Cleanup ---
Write-Host "Disconnecting from Microsoft Graph." -ForegroundColor Yellow
Disconnect-MgGraph 
Write-Host "Disconnected from Microsoft Graph." -ForegroundColor Green
