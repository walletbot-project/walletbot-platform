1. (Attached video 1 and 2)

The iPhone 14 video shows the most important features. I show registration process, adding accounts, categories, tags and expenses, settings (lang, currency) and assistant via text. I also show offline mode, sync recovery and local only accounts. I also show how to report a message. At the end of the video I show live voice mode working.

The iPad video shows Apple and Google signin and account deletion process.

2. App description:

A personal expenses tracker with a AI chat and voice mode assistant. Allows users to track expenses and incomes, organize in categories, accounts and tags.

The problem it solves: most people abandon expense apps because typing every purchase takes too long. Saying "coffee, four thousand pesos, card" takes two seconds. This is the main value proposition.

The app also is online first and with supports multi account and device only accounts to provide all the options to different users. This adds value too.

Audience: adults tracking their own money. Argentina and the United States are the primary markets. Our terms set an 18+ minimum. There is no shared, social or multi-user content.

3. Setup and access

To start using the app you need to create an account.

You can use local accounts (no auth needed) or any google or apple account or by using these credentials:
email: jonhdoe@walletbot.live
password: 66667777

There is no feature difference between local accounts, online accounts using google, apple or user/pass auth. Different rate limits to AI agents may apply.

After you are inside you can try the following features:
- 1. Registering accounts, categories, tags
- 2. Manually adding an expense
- 3. Reading and editing expenses
- 4. Using the AI chat to add expenses and incomes. Try "Yesterday I spent 13 dollars on coffee and 20 dollars on groceries". You can also ask about past expenses/incomes.
- 5. Report message or full conversation.
- 6. Add or edit home widgets (either manually or asking the assistant)
- 7. Account deletion. We immediately delete all your data after confirmation vía email.

No paid content, no in-app purchases, no subscriptions. The app is free and complete.

On user-generated content: transactions and assistant conversations are private to the account and are never shown to other users. Nothing is shared or published, so there is no one to block. The reporting control above covers AI responses.

4. External services

- Convex (US): backend database, sync API and function hosting.
- Better Auth, running on our Convex backend: email and password accounts and sessions.
- Google Sign-In and Sign in with Apple: authentication.
- Google Gemini Live API (gemini-3.1-flash-live-preview): the speech-to-speech assistant. The device streams microphone audio to Google over a session token minted by our backend. Audio is not stored.
- Resend: transactional email (verification, password reset, deletion confirmation).
- Amazon SES: inbound support email to support@walletbot.live.
- Grafana Cloud: backend telemetry and diagnostics.
- dolarapi.com and api.frankfurter.dev: exchange rate quotes, fetched by our backend on a schedule, never by the app.

5. Regional differences

The only difference is the default language and currency, which can be changed. No other difference or gated feature.


6. Regulated industry or third-party material

Not applicable. The app does not move, hold or transfer money, does not connect to banks or card networks, and provides no financial, tax or investment advice. Users type in their own numbers. Exchange rates come from the public providers listed above and are shown for reference. There is no licensed, protected or third-party content in the app.