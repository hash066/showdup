# Google Play listing draft

## App name

ShowdUp

## Short description

An alarm you have to show up for. Your phone checks, so there is no snooze.

## Full description

Snooze buys time. Showing up ends the alarm.

ShowdUp is an alarm clock for the promise you keep breaking. You pick the time
and what showing up means. It rings, and it keeps coming back until your phone
can tell you actually did it. There is no “done” button to lie to.

What can count as showing up:

- Steps walked during the window, counted by your phone.
- Phone left alone, with a timer that resets if you pick it up.
- A tag you place across the room, scanned with Google's own scanner.
- LeetCode problems solved, read from your public profile (beta).

With Pro you can also arrive at a place, reach a gym, or walk a distance by GPS.

Every alarm has a window. Reminders keep arriving inside it, at the gap you
choose, up to the number you choose. Proof stops them. If the day falls apart,
hold “End today” — it stops the reminders and records an honest ended day, with
no guilt and no lost streak. If a sensor or permission fails, the day is
recorded as “your phone couldn't tell”, never as a miss.

Hold an app until you show up: choose an app you reach for first thing. During
the window ShowdUp catches it — the first time with a screen that explains the
rule and offers to end the day, and after that with a small card that says
“Caught.” before Android goes home. The moment you show up, it opens again.
This uses Android's Accessibility service, with your permission, to see only
which app came to the front. ShowdUp never reads your screen, what you type,
your notifications or your passwords, and you can switch it off in Android
settings at any time. Your phone app, messages, Settings and emergency apps are
never held.

History shows your rhythm over four weeks, your longest streak and the days you
tend to miss. A companion sits with you: a dot for everyone, animals with Pro.
Battles are a private weekly scoreboard with up to ten friends.

Free: one proof alarm, one held app, seven days of history, the dot companion.
Pro: 20 proof alarms, gym, places and GPS walks, a different time each day, two
years of history and patterns, every app held, animal companions, and battles of
ten. ₹79 a month or ₹399 a year with 7 days free. Google Play shows the final
price before you pay, and a subscription renews until you cancel it in Google
Play.

Alarms, history and proof stay on your phone. Nothing about what you did is
uploaded. Battles sync only a name you choose, a companion and weekly scores.
You can erase everything from Settings.

## Match the listing to the build

Every feature named above must be switched on in the uploaded build. The
release script builds without `FEATURE_CATCH`, so unless the catch ships, delete
the "Hold an app until you show up" paragraph and the held-app words in the
Free and Pro lines before saving the listing. Battles need live Firebase
functions; if they are not deployed, drop the Battles sentence and "battles of
ten". The Pro page in the app already hides both when they are off.

## Screenshots and graphics

`store-assets/README.md` lists the six phone screenshots, the icon and the
feature graphic in upload order, and how to re-render them from the app code.
Screenshots from sample data keep the visible "Preview · sample data" label;
replace them with real-device screens once those flows pass device testing.
