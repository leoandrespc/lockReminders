# LockReminders

LockReminders is a World of Warcraft addon for the Forever client. It keeps a row of missing buffs on screen, and it pops a separate alert when a talent procs, a spell fully misses, your health or mana drops, or a warlock soulstone, Banish, or soul shard needs attention.

Settings are saved in `LockRemindersDB` for the whole account. Class tools only appear on the characters that can use them.

Open the window from the minimap button, or with `/lr`. Drag the minimap button around the minimap to park it.

## Buffs

Search your spellbook by name and add the auras you want to watch. Each one can show in a raid, in a party, or always. The **When adding** choice on this tab is the scope used by `/lr add` when you do not type one.

The alert is a row of icons for what is missing or about to expire. A short countdown sits on an aura during its last seconds. Drag the border to move the row, or use `/lr arrange` to reorder the icons. `/lr lock` keeps the row still.

Warlocks and hunters can add a **Pet** reminder. It shows when the pet is not out. A sacrificed warlock pet does not count as missing.

## Items

Food buffs and food items live here, along with the warlock **Healthstone**.

A food buff reminds you in a raid when that buff is down. A food item can also be marked to alert in combat. The healthstone icon shows when you have none in your bags. Both follow the same Raid, Party, and Always checks as buffs.

## Procs

Pick a talent whose proc you want announced. Nightfall, for example, watches for Shadow Trance. The alert shows the buff icon, holds for a few seconds, and can play a sound and flash the screen. Size, hold time, sound, and position are set from the talent's own alert screen.

## Spell misses/resist

Add your spells and your pet's spells. The alert fires only when one of those spells fully misses or is fully resisted.

A partial resist still landed, so it stays quiet. Dodge, parry, absorb, and block stay quiet too. A Fear that lands does not alert. A Shadow Bolt that hits for a reduced amount does not alert.

Interrupts such as Spell Lock are not judged by damage. The alert fires when the interrupt misses: the target keeps casting, and the silence never lands.

**Immune** is its own gold alert. It covers every spell you and your pet cast, not only the ones on the miss list. It has its own on/off switch and a Test button next to Move.

## Status

This tab is for you, on any class.

**Speed** shows your movement and your target's movement as a percent of run speed. Standing still reads 0%.

**Low health** and **Low mana** appear when you drop under the percent you set. The line stays up for the number of seconds you choose, then hides until you climb back above that line and drop under it again. The text is yours. The default lines are `LOW HEALTH` and `LOW MANA`. Each line has its own sound.

**Effect** is how that text moves: None, Pulse, Shake, Bounce, Flash, or Pop. The motion is on the letters, not on an icon.

## Warlock

This tab is only on a warlock. It holds four alerts, and each one has Raid, Party, and Always, a size, Move, and Test.

**Missing stone** glows when you are not carrying a soulstone. It uses the soulstone sound.

**On screen** lists people who currently have your soulstone, with a live timer. **Full name** keeps the full character name. **Frame** draws or hides the purple border around that list.

**Banish** shows the spell icon and a countdown during the last seconds you set. The text under the icon defaults to `BANISH`, and the mob name sits under that.

**Soul shards** shows the shard icon with the count inside it. At zero the number turns red and the text under the icon appears. That text defaults to `NO SHARDS`. Clear the box and the alert is only the icon and the number. The sound plays when the count crosses from one or more down to zero.

## Sounds

These sounds are in the addon, so they do not depend on a kit the game is already using:

None, Pulse, Drip, Knock, Chime, Bloom, Rise, Tick, Hum, Spark, Glass, Beep, Buzz, Chirp, Pop, Ding, Sweep, Clap, Warp.

Miss alerts can also use the game's Ping. Click a sound in the options to hear it.

## Moving an alert

Every on-screen alert has **Move** and **Test**. Move lets you drag that alert. Test shows it where it will appear, including the samples for the soulstone list, Banish, and an empty shard bag. Press the button again when it says Done or Stop.

## Commands

| Command | What it does |
| --- | --- |
| `/lr` | Opens or closes the window. `/lockreminders` does the same. |
| `/lr help` | Prints this list in chat. |
| `/lr lock` | Locks or unlocks the buff row. |
| `/lr arrange` | Reorders the icons in the buff row. |
| `/lr buffs` | Lists the buffs you can read, with their spell IDs. |
| `/lr add 12345` | Adds that aura with the scope chosen in When adding. |
| `/lr add 12345 always` | Adds it for Always, Party, or Raid. |
| `/lr food 12345` | Tracks that food buff. In a raid it alerts when the buff is missing. |
| `/lr remove 12345` | Removes that aura or food buff. |
| `/lr spells` | Opens Spell misses/resist. `/lr miss` does the same. |
| `/lr misc` | Opens Status. |
| `/lr soul` | Opens the Warlock tab. Warlocks only. |
| `/lr reset` | Restores every option to its default and clears your lists. |

## Requirements

Forever client, Interface 16001. Copy the `LockReminders` folder into `Interface/AddOns` and `/reload`.
