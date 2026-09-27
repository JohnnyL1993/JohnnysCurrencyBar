# Johnny's Currency Tracker

A World of Warcraft 3.3.5a addon for the Warmane private server.

Draggable bar tracking Honor, Arena Points, Stone Keeper's Shards, Wintergrasp Marks of Honor, and Emblems (Heroism/Valor/Conquest/Triumph/Frost). Same look as Johnny's Warmane Addon Hub.

## Requirements

No other addons required.

## Install

1. Go to [Releases](https://github.com/JohnnyL1993/JohnnysCurrencyBar/releases) and download **`JohnnysCurrencyBar-vX.Y.zip`** from the latest release.
   Don't use GitHub's green **Code → Download ZIP** button or the "Source code" zips. Those unpack as `JohnnysCurrencyBar-main` or `JohnnysCurrencyBar-1.0`, and WoW won't load an addon whose folder name doesn't match.
2. Extract it into `World of Warcraft\Interface\AddOns\`. You should end up with `Interface\AddOns\JohnnysCurrencyBar\JohnnysCurrencyBar.toc`.
3. Restart WoW, or log out to the character screen, and make sure the addon is enabled.

## Updating

Download the latest release zip, delete the old `JohnnysCurrencyBar` folder, and extract the new one in its place.

## Slash commands

| Command | What it does |
| --- | --- |
| `/curbar` | Show or hide the currency bar |

## Other Johnny's addons

- [Johnny's Raid Comp](https://github.com/JohnnyL1993/JohnnysRaidComp)
- [Johnny's Warmane Addon Hub](https://github.com/JohnnyL1993/JohnnysAddonHub)
- [Johnny's Blacklist](https://github.com/JohnnyL1993/JohnnysBlackList)
- [Johnny's Gear Advisor](https://github.com/JohnnyL1993/JohnnysGearAdvisor)
- [Johnny's Messenger](https://github.com/JohnnyL1993/JohnnysMessenger)
- [Johnny's Raid Browser](https://github.com/JohnnyL1993/JohnnysRaidBrowser)
- [Johnny's Raid Roll](https://github.com/JohnnyL1993/JohnnysRaidRoll)

## Releasing (maintainer notes)

1. Bump `## Version:` in the `.toc`.
2. Commit, then `git tag vX.Y` and `git push && git push --tags`.
3. The **Release** GitHub Action builds the zip and attaches it to the release.
