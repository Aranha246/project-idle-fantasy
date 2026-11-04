# GDD: Project Idle Fantasy (Godot 4.7)

## 1. Executive Summary
* **Genre:** Medieval Fantasy Idle / Incremental RPG
* **Platforms:** PC (Steam/Desktop) & Mobile (Android)
* **Target Audience:** Casual gamers, strategy enthusiasts, auto-play RPG lovers.
* **Core Loop:** Idle Questing/Combat -> Tiered Currency & Gear Loot -> Upgrades & Stat Allocation -> Unlocking Higher Difficulty Zones.

## 2. Economy & Currency Systems
* **Tiered Currency:**
  - 100 Copper (CP) = 1 Silver (SP)
  - 100 Silver (SP) = 1 Gold (GP)
  - 100 Gold (GP) = 1 Platinum (PP)
* **Progression Loop:**
  - Defeating mobs yields XP and Copper.
  - Automatic currency conversion handles scaling numbers cleanly.

## 3. Data Architecture & Node Structure
* **CurrencyManager (Autoload/Global):** Handles currency storage, additions, subtractions, and tier calculations.
* **GameManager (Autoload/Global):** Manages global game ticks (idle timer), zone level, and offline gains.
* **PlayerState (Resource):** Stores stats (Attack, Defense, Attack Speed), equipped gear, and current XP.
* **InventoryManager (Node/Autoload):** Manages a grid-based storage array of ItemResources.

