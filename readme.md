# Promoting Copilot Chat

![](images/logo2.png)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
## Audience

This guide is intended for **IT administrators and Change Management teams** in charge of user adoption for new tools in Microsoft 365 (in this case, the Copilot Chat app). It provides a strategy and technical steps to promote a newly available feature (Copilot Chat) to a large number of users efficiently and safely.

---
## Promoting Awareness for the Newly Pinned Copilot Chat App

**Microsoft 365 Copilot Chat** is your AI assistant, built right into Microsoft 365—at no extra cost. It is designed to help everyone in your organization use AI naturally in their flow of work—whether they need quick info, a starting point, or a creative boost. And because it is part of Microsoft 365, it is build on security you can trust.
Now that Copilot Chat is pinned and easy to find, it is the perfect time to spread the word.

IT Admins and Change Management teams can use the Nudge App to prompt users with a friendly message like, `“Hey, try Copilot Chat! Just type your request in the prompt and get started.”` This simple nudge helps users quickly discover how powerful—and helpful—Copilot Chat can be.

---
## Available Options



### Script-based Teams Nudge App
[This document](https://github.com/luishdemetrio/copilot_chat_promotion/blob/main/instructions/PowerShell%20Promoting%20Copilot%20Chat%20on%20Teams.pdf) provides guidance on deploying a PowerShell script that sends Adaptive Card messages to users in Microsoft Teams. The script uses the Microsoft Graph API for 
communication, and it employs parallel processing to work efficiently while reducing file input and output operations. 

The Adaptive Card, which is central to the script, contains six buttons. Each button corresponds to a specific prompt. When a user clicks on a button, the card triggers an action that opens a new browser tab. The chosen prompt is automatically copied into a dialog box in the browser. 

The user can then review the prompt, make edits to modify it if needed, and click a "Send" button to execute the prompt. This interactive design allows users flexibility to tailor the prompt before sending. 

More details at: [PowerShell Instructions](https://github.com/luishdemetrio/copilot_chat_promotion/blob/main/instructions/PowerShell%20Promoting%20Copilot%20Chat%20on%20Teams.pdf)


### Low-touch ACM Flow

[This solution](https://github.com/luishdemetrio/copilot_chat_promotion/blob/main/instructions/Power%20Automate%20Promoting%20Copilot%20Chat%20on%20Outlook.pdf) enables IT Admins to send an email message to users with the Copilot Chat campaign via Power Automate. This integration simplifies communication workflows and enhances user engagement with the campaign.

More details at: [Power Automate Instructions](https://github.com/luishdemetrio/copilot_chat_promotion/blob/main/instructions/Power%20Automate%20Promoting%20Copilot%20Chat%20on%20Outlook.pdf)

### 🤝 Contributing

We welcome contributions! 

- Code standards and conventions
- Pull request process
- Issue reporting
- Feature requests


### 🙋 Support

- [Feedback & Issues](https://github.com/luishdemetrio/copilot_chat_promotion/issues)