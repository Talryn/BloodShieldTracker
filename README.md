## Issues / Feedback

Please use the Ticket Tracker at Wowace to report bugs or request enhancements: http://www.wowace.com/addons/blood-shield-tracker/tickets/

## Overview

Blood Shield Tracker is an addon to track the value of the Death Knight Blood Shield. It can show bars for the following items:

* The current Blood Shield value (when Blood Shield is up).
* The estimated heal of a Death Strike or the Blood Shield value based on Resolve.
* The current Power Word:Shield value on the player.
* The current and maximum health of the player.

### Blood Shield Bar

* Appears when Blood Shield is up and shows the current shield value.
* Updates the current value of the Blood Shield. It provides both an absolute value and a percent of the remaining shield value. With stacking Blood Shields, the maximum and percent values are less useful but it might be interesting for some people so I left that option. The current value is key thing to use.
* Disappears when the Blood Shield buff ends.

### Estimate Bar

* Predicts the size of the Death Strike heal or Blood Shield based on Resolve.
* The user can configure if the bar predicts the Death Strike heal or Blood Shield value.
* The bar can be configured to show the estimated value as a percentage of maximum health instead of the absolute value.

### Bone Shield Bar

* Shows the current number of Bone Shield charges, time left on the buff, or the time until Bone Shield is usable again.

### Power Word: Shield Bar

* Shows the current value of the Power Word: Shield on you. It is shown when a shield is on you and hidden when no PW:S is on you.
* By default this bar includes the Divine Aegis shield too. You can disable that in the options if you wish though.
* It is fully configurable just like the other bars.

### Total Absorbs Bar

* Shows the total of various absorbs on you. It includes the following absorb types and you can configure which ones you want included:
    * Blood Shield
    * Power Word: Shield
* It is fully configurable just like the other bars.

### AMS Bar

* Provides a bar to track the remaining absorb from Anti-Magic Shield.
* It is off by default and needs to be enabled first.

### Health Bar

* Provides a health bar to make monitoring your health easier. Based on your UI setup, you may find this very useful to keep near the other Blood Shield Tracker bars and your rune addon of choice.
* It is off by default and needs to be enabled first.
* It is fully configurable and has an option to change color based on a user-set threshold.

### LDB / Minimap Data

The LDB or minimap icon provides a tooltip with some statistics for your Blood Shields. The following statistics are provided for the session and for the last fight:

* The total number of blood shields.
* The number of shields refreshed. This is the number that are re-applied before the previous shield was removed (i.e., stacking).
* The number of removed shields.
* The minimum, maximum, and average shields maximum/starting values. The maximum value is the full, initial value of the shield.
* The total amount absorbed by the shields, the total value of all shields, and percent of the shields used. This lets you see how much of the shields were used to absorb damage.

In addition, for the last fight it provides:

* The duration of the fight.
* The average number of seconds between Blood Shields (or successful Death Strikes).

The LDB can be configured to use a shorter label and can also set a data feed to display values such as the last Death Strike, last Blood Shield, and the Estimate Bar value.
Options

Blood Shield Tracker provides several configuration options. It also supports LibSharedMedia so fonts and textures loaded there can also be used. It also provides full support for profiles.

You can change the following:

* If the minimap button is shown. The addon also provides an LDB data feed.
* Whether a bar is shown.
* If a bar is locked and cannot be moved.
* The width, height, and scale of the bars
* The font, font size, and font options of the text on the bars
* Whether the background/bar is shown or just the text.
* The color of each bar and bar text, including setting the minimum and optimal heal colors.
* The texture to use for each bar.
* Whether a bar has a Blizzard-style border around it.
* The format of the text on a bar.

### Skinning

Blood Shield Tracker provides support for skinning. In particular, it will match the look and feel of ElvUI and Tukui. There are settings in the configuration to control it selectively. By default, it will override the textures, font, and borders of the bars to match the UI. The user will just need to position the bars to where he or she would like them. If you do change the Skinning settings, you will need to reload the UI since the changes are only made when the addon loads.

If you need to access the configuration but cannot find it, you can always type /bst in a chat window.