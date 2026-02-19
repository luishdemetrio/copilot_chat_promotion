# Requires PowerShell 7.0 or later for ForEach-Object -Parallel
# Requires the ImportExcel and Microsoft.Graph modules (Graph.Teams, Graph.Authentication)

# --- Load Required Modules ---
Import-Module ImportExcel -ErrorAction Stop
Import-Module Microsoft.Graph.Teams -ErrorAction Stop
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

# --- Authentication ---
# Connect to Microsoft Graph with required scopes (Chat.ReadWrite for messaging, User.Read for user info)
$scopes = @("Chat.ReadWrite", "User.Read")
try {
    Connect-MgGraph -Scopes $scopes -ErrorAction Stop
    $myUserAccount = (Get-MgContext).Account  # Current account (user) used for sending messages
    Write-Host "Successfully connected to Microsoft Graph as $($myUserAccount)" -ForegroundColor Green
} catch {
    Write-Error "Failed to connect to Microsoft Graph. Ensure the necessary modules and permissions are present. Error: $($_.Exception.Message)"
    exit
}

# --- Input Data ---
# Path to Excel file containing a list of user UPNs (User Principal Names) to send messages to
$excelFilePath = "C:\Users\avichandra\Downloads\CopilotChat-Nudges\Users.xlsx"
if (-not (Test-Path $excelFilePath)) {
    Write-Error "Input Excel file not found at: $excelFilePath"
    exit
}
try {
    $upns = Import-Excel -Path $excelFilePath | Select-Object -ExpandProperty UPN
    if (-not $upns -or $upns.Count -eq 0) {
        Write-Warning "No UPNs found in the Excel file. Aborting."
        exit
    }
    Write-Host "Loaded $($upns.Count) user UPNs from Excel." -ForegroundColor Green
} catch {
    Write-Error "Failed to import data from Excel file. Error: $($_.Exception.Message)"
    exit
}
$upns = @($upns)  

# --- Output Log File Setup ---
$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$logFolder  = "C:\Users\avichandra\Downloads\CopilotChat-Nudges"
$logFile    = Join-Path $logFolder "CopilotMessageLog_$timestamp.csv"
# Ensure the log directory exists
if (-not (Test-Path $logFolder)) {
    New-Item -Path $logFolder -ItemType Directory -Force | Out-Null
}
# Create or overwrite the log file with headers
"Timestamp,UPN,Status,Message" | Out-File -FilePath $logFile -Encoding UTF8 -Force

# --- Adaptive Card Setup ---
# Path to the Adaptive Card JSON file
$adaptiveCardPath = "C:\Users\avichandra\Downloads\CopilotChat-Nudges\adaptivaCardActions.JSON"
if (-not (Test-Path $adaptiveCardPath)) {
    Write-Error "Adaptive Card JSON file not found at: $adaptiveCardPath"
    exit
}
try {
    $adaptiveCardJson = Get-Content -Path $adaptiveCardPath -Raw -Encoding UTF8
    Write-Host "Successfully loaded Adaptive Card JSON." -ForegroundColor Green
} catch {
    Write-Error "Failed to load Adaptive Card JSON file. Error: $($_.Exception.Message)"
    exit
}

# --- Configuration: Throttling and Batching ---
$retryLimit   = 3       # Total attempts per user (including first try and retries)
$batchSize    = 500    # Number of users to process in each batch (tune as needed for performance)
$throttleLimit = 5      # Max parallel threads (tune this to avoid throttling; 5-10 is a safe start)

# --- Parallel Processing with Batching ---
Write-Host "Starting message send to $($upns.Count) users in batches of $batchSize (parallel threads: $throttleLimit)..." -ForegroundColor Yellow

$totalBatches = [math]::Ceiling($upns.Count / $batchSize)
# Measure the time taken for sending messages
$timeTaken = (Measure-Command {
    for ($batchIndex = 0; $batchIndex -lt $totalBatches; $batchIndex++) {
        # Determine the range for this batch
        $startIndex = $batchIndex * $batchSize
        $endIndex   = [math]::Min($startIndex + $batchSize - 1, $upns.Count - 1)
        $batchUsers = $upns[$startIndex..$endIndex]

        Write-Host "Processing batch $($batchIndex + 1) of $totalBatches - Users $startIndex to $endIndex (Count: $($batchUsers.Count))" -ForegroundColor Cyan

        # Parallel send for the current batch of users
        $batchResults = $batchUsers | ForEach-Object -Parallel {
            # Note: Inside this script block, use $using:<var> to access variables from the parent scope.
            param($using) # (No explicit parameters needed; using variables will be captured from parent scope)
            # Small random delay to stagger threads and reduce simultaneous API calls
            Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 500)

            $userUPN = $_
            # Attempt to create chat and send message, with retries on failure.
            for ($attempt = 1; $attempt -le $using:retryLimit; $attempt++) {
                try {
                    # Create a 1:1 chat (or get existing chat) with the target user and the sender (current account)
                    $chatParams = @{
                        chatType = "oneOnOne"
                        members  = @(
                            @{
                                "@odata.type"    = "#microsoft.graph.aadUserConversationMember"
                                roles            = @("owner")
                                "user@odata.bind" = "https://graph.microsoft.com/v1.0/users('$($userUPN)')"
                            },
                            @{
                                "@odata.type"    = "#microsoft.graph.aadUserConversationMember"
                                roles            = @("owner")
                                "user@odata.bind" = "https://graph.microsoft.com/v1.0/users('$($using:myUserAccount)')"
                            }
                        )
                    }
                    $chat = New-MgChat -BodyParameter $chatParams -ErrorAction Stop
                    $chatId = $chat.Id
                    if (-not $chatId) {
                        throw "Failed to create or retrieve chat ID for $userUPN"
                    }

                    # Prepare the chat message with the Adaptive Card attachment
                    $attachmentId = [Guid]::NewGuid().ToString()
                    $messageBody  = @{
                        contentType = "html"
                        content     = "<attachment id='$attachmentId'></attachment>"
                    }
                    $attachment   = @{
                        id          = $attachmentId
                        contentType = "application/vnd.microsoft.card.adaptive"
                        content     = $using:adaptiveCardJson
                    }

                    New-MgChatMessage -ChatId $chatId -Body $messageBody -Attachments @($attachment) -ErrorAction Stop

                    # If successful, output a success log entry and break out of the retry loop
                    return [PSCustomObject]@{
                        Timestamp = (Get-Date).ToString('u')
                        UPN       = $userUPN
                        Status    = "Success"
                        Message   = "Message sent"
                    }
                    #break
                }
                catch {
                    # Capture error information
                    $errorMessage = $_.Exception.Message
                    $retryAfterSec = 0
                    # Check for Microsoft Graph throttling (Retry-After header)
                    if ($_.Exception.Response -and $_.Exception.Response.Headers["Retry-After"]) {
                        $retryAfterSec = [int]$_.Exception.Response.Headers["Retry-After"]
                        $errorMessage += " (Retry-After: $retryAfterSec sec)"
                    } else {
                        
                        
                        if ($errorMessage -like "*Failed to find users with user principal name*" -or 
                            $errorMessage -like "*Duplicate chat members is specified in the request body*") {
                                Write-Host "Skipping: User not found."
                                # Final attempt failed – log an error entry
                               return  [PSCustomObject]@{
                                    Timestamp = (Get-Date).ToString('u')
                                    UPN       = $userUPN
                                    Status    = "Error"
                                    Message   = $errorMessage
                                }
                        }
                        #break

                        # Compute exponential backoff delay (in seconds) with jitter for transient errors
                        if ($attempt -eq 1) {
                            $retryAfterSec = 3 + (Get-Random -Minimum 1 -Maximum 4)   # initial delay: ~6-8 sec
                        } else {
                            $retryAfterSec = (3 * [math]::Pow(2, $attempt - 1)) + (Get-Random -Minimum 1 -Maximum 4)
                        }
                    }

                    if ($attempt -lt $using:retryLimit) {
                        # Log the retry attempt and wait before next attempt
                        [PSCustomObject]@{
                            Timestamp = (Get-Date).ToString('u')
                            UPN       = $userUPN
                            Status    = "Retry $attempt"
                            Message   = "Waiting $retryAfterSec seconds - $errorMessage"
                        }
                        Start-Sleep -Seconds $retryAfterSec
                        # Continue to next attempt
                    } else {
                        # Final attempt failed – log an error entry
                        [PSCustomObject]@{
                            Timestamp = (Get-Date).ToString('u')
                            UPN       = $userUPN
                            Status    = "Error"
                            Message   = $errorMessage
                        }
                        # (Loop will end naturally after this since it's the last attempt)
                    }

                    
                }
            }  # end for (attempt)
        } -ThrottleLimit $throttleLimit

        # Append the batch results to the CSV log file
        if ($batchResults) {
            # Export batch results without adding header (header already written)
       
            $cleanResults = $batchResults | Where-Object {
                $_.Timestamp -and
                $_.UPN 
            }

            if ($cleanResults.Count -gt 0) {
                $cleanResults | Export-Csv -Path $logFile -NoTypeInformation -Encoding UTF8 -Append -Force
            }
            
        }
        Write-Host "Batch $($batchIndex + 1) of $totalBatches completed. Logged $($cleanResults.Count) entries." -ForegroundColor Green

        # Short pause between batches to avoid continuous load (adjust or remove if not needed)
        Start-Sleep -Seconds 5
    }
}).TotalMinutes

Write-Host "Parallel processing finished." -ForegroundColor Yellow
Write-Host ("Total Time Taken: {0:N2} minutes" -f $timeTaken) -ForegroundColor Yellow

# --- Completion and Cleanup ---
Write-Host "Log file is available at: $logFile" -ForegroundColor Green

Write-Host "Disconnecting from Microsoft Graph..." -ForegroundColor Yellow
Disconnect-MgGraph
Write-Host "Disconnected from Microsoft Graph. Script execution completed." -ForegroundColor Green

