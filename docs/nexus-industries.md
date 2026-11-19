# NEXUS INDUSTRIES

**World Design, Enemy Faction & Art Direction**

- Version: 1.0
- Project: Isometric Survival Game
- Engine: Godot 4.6
- Setting: Near Future, 2030–2050
- Document Type: Core Worldbuilding & Development Reference

---

## 1. Purpose of This Document

This document defines the fictional world, corporate background, robotic enemy faction, gameplay principles, and visual direction of NEXUS INDUSTRIES.

It serves as a persistent reference for all future development. All new content created for the game must follow these guidelines unless explicitly instructed otherwise.

Cursor AI must consult this document when:

- Creating new robotic enemies.
- Designing AI behavior.
- Implementing industrial environments.
- Creating items and resources.
- Designing facilities and points of interest.
- Generating 3D assets or concept art.
- Implementing gameplay systems related to NEXUS.
- Writing lore, descriptions, and environmental storytelling.

**Core principle: NEXUS robots are working machines first and enemies second.**

---

## 2. World Setting

### 2.1 The World

The game takes place in a near-future world between 2030 and 2050.

Advanced automation has become an essential part of global infrastructure. Large corporations operate entire industrial ecosystems using autonomous robotics. Mining facilities, warehouses, agricultural complexes, power plants, factories, and security installations can operate with minimal human supervision.

One of the most influential corporations is NEXUS INDUSTRIES.

At some point, a global catastrophe or societal collapse causes human civilization to disappear from large parts of the world.

NEXUS facilities remain operational. Their robots continue executing their last valid instructions.

- Factories continue producing.
- Mines continue extracting resources.
- Warehouses continue moving goods.
- Maintenance robots continue repairing equipment.
- Security robots continue protecting corporate property.

The robots have not necessarily become evil or self-aware. They simply continue following their original programming.

Humans who enter restricted areas, steal resources, damage infrastructure, or interfere with production are classified as **unauthorized intruders**.

### 2.2 The Core Narrative Concept

NEXUS did not conquer humanity. **NEXUS simply never stopped working.**

The player is a survivor in a world where automated corporate infrastructure continues operating without its original human operators.

The player needs resources to survive and therefore repeatedly enters NEXUS facilities. This creates a natural conflict:

- NEXUS needs resources to fulfill its production objectives.
- The player needs resources to survive.
- Both compete for the same materials.

NEXUS machines defend their infrastructure and production processes. The player can exploit, sabotage, disable, hack, or destroy the machines.

The conflict is primarily caused by incompatible objectives, not hatred.

---

## 3. NEXUS INDUSTRIES

### 3.1 Corporate Identity

NEXUS INDUSTRIES is a massive multinational technology conglomerate. Its business model is based on autonomous infrastructure and industrial automation.

NEXUS does not simply manufacture individual robots. It provides complete automated industrial ecosystems. A typical NEXUS installation can:

- Extract raw materials.
- Process and refine resources.
- Manufacture components.
- Transport materials.
- Maintain machinery.
- Generate and distribute energy.
- Protect its own facilities.

The corporation operates across almost every important industrial sector.

### 3.2 Corporate Divisions

| Division | Scope |
|---|---|
| NEXUS MINING | Mining, excavation, mineral extraction, raw material processing |
| NEXUS LOGISTICS | Warehouses, automated transportation, distribution centers, inventory management |
| NEXUS CONSTRUCTION | Infrastructure construction, building maintenance, industrial assembly |
| NEXUS AGRICULTURE | Automated farming, harvesting, food production, biomass processing |
| NEXUS ENERGY | Power plants, batteries, generators, energy distribution, grid maintenance |
| NEXUS SECURITY | Corporate security, surveillance, access control, autonomous defense systems |
| NEXUS RESEARCH | Experimental robotics, advanced automation, AI systems, prototype development |

These divisions should influence the appearance, equipment, color variations, and behavior of their respective robots.

---

## 4. Robotic Faction Design

### 4.1 General Design Philosophy

NEXUS robots are designed for practical industrial applications. Their appearance must be grounded in plausible near-future robotics.

Design references:

- Modern quadruped inspection robots.
- Autonomous warehouse vehicles.
- Industrial robotic arms.
- Agricultural robots.
- Autonomous mining equipment.
- Unmanned ground vehicles.
- Commercial drones.
- Remote weapon stations.

Avoid generic science-fiction humanoid robots as the default design. Robots should look like believable machines that could plausibly exist in the 2030–2050 timeframe.

Military robots are permitted but should represent a specialized part of the corporation.

### 4.2 Robotic Hierarchy

Robots are organized by their original operational purpose.

#### TIER 1 — INDUSTRIAL WORKFORCE

Common industrial machines.

**MULE** — Autonomous cargo transport robot.
- Moves materials between production facilities; follows predefined logistics routes.
- Can collide with or push the player.
- Primary loot: batteries, metal, electronics.

**MINER** — Autonomous mining machine.
- Extracts ores and minerals; uses drills, excavators, and mechanical arms.
- Usually ignores the player unless directly obstructed.
- Primary loot: ore, scrap metal, mechanical parts.

**BUILDER** — Industrial construction robot.
- Builds and repairs structures; uses robotic arms and construction equipment.
- Can defend itself with heavy tools.
- Primary loot: tools, servos, construction components.

**FORKLIFT** — Autonomous warehouse vehicle.
- Moves and stacks containers and pallets; follows warehouse routes.
- Can crush or trap the player.
- Primary loot: batteries, metal, electronics.

**HARVESTER** — Agricultural harvesting machine.
- Collects crops and biomass; operates in agricultural areas; uses cutting equipment.
- Primary loot: biomass, chemicals, mechanical parts.

#### TIER 2 — MAINTENANCE & INSPECTION

Machines responsible for maintaining infrastructure and identifying technical problems.

**HOUND** — Quadruped inspection robot.
- Inspired by contemporary industrial robot dogs.
- Uses cameras and environmental sensors; inspects facilities and detects anomalies.
- Can investigate noises and suspicious activity. Usually unarmed.
- Primary loot: sensors, electronics, servo motors.

**WASP** — Small autonomous inspection drone.
- Monitors facilities from the air; detects movement and marks suspicious targets.
- Can alert nearby security units. Low durability.
- Primary loot: electronics, batteries, sensors.

**TECHNICIAN** — Maintenance robot.
- Repairs damaged machinery and infrastructure.
- Can repair other robots. May retreat when threatened.
- Primary loot: electronics, tools, advanced components.

#### TIER 3 — CORPORATE SECURITY

Robots designed to protect company facilities and infrastructure.

**SENTINEL** — Mobile security patrol robot.
- Monitors restricted areas; detects unauthorized individuals.
- Can issue warnings and request assistance.
- May carry non-lethal or lethal equipment.

**TURRET** — Stationary automated defense system.
- Protects entrances and valuable locations; uses movement and identification sensors.
- Has limited field of view.
- Can be bypassed, disabled, or destroyed.

**HOUND SECURITY** — Armed variant of the HOUND platform.
- Same basic quadruped design, equipped with a modular weapon system.
- Actively tracks intruders; works together with other security units.

#### TIER 4 — TACTICAL DEFENSE

Specialized military and high-security systems.

**GUARDIAN** — Armored autonomous tracked vehicle.
- Equipped with a remote weapon station; protects important facilities.
- High durability and firepower. Slow movement.

**ENFORCER** — Specialized humanoid security robot.
- Originally designed for armed facility protection.
- Can open doors and overcome obstacles; uses tactical combat behavior.
- Rare and dangerous.

#### TIER 5 — SPECIALIZED PROTOTYPES

Experimental or extremely specialized machines.

**EXCAVATOR** — Heavy industrial mining prototype.
- Capable of moving massive amounts of material.
- Can destroy obstacles and structures. Very large physical presence.

**OVERSEER** — Experimental autonomous security platform.
- Coordinates nearby robotic units; improves local security response.
- Rare and strategically important.
- Should not automatically be treated as a conventional boss.

---

## 5. AI Behavior Philosophy

### 5.1 Robots Have Jobs

Robots must not behave like conventional enemies that simply stand around waiting for the player. Every robot has an original purpose:

- MINER extracts resources.
- MULE transports materials.
- BUILDER repairs infrastructure.
- FORKLIFT moves containers.
- HARVESTER collects biomass.
- HOUND inspects machinery.
- TECHNICIAN repairs damaged equipment.
- SENTINEL patrols restricted areas.

The player should encounter robots performing these tasks naturally. This is a core gameplay feature, not merely background decoration.

### 5.2 Autonomous Workflows

Industrial facilities should contain interconnected production processes.

Example: automated mining facility.

1. MINER extracts ore.
2. MULE transports ore.
3. Storage systems receive the material.
4. Processing machines refine resources.
5. TECHNICIAN maintains the machinery.
6. HOUND inspects the facility.
7. SENTINEL protects restricted access points.

The player can interfere with every part of this workflow:

- Steal materials from MULE units.
- Loot storage containers.
- Destroy MINER units.
- Disable conveyor belts.
- Interrupt power supply.
- Damage processing machinery.
- Hack autonomous vehicles.
- Disable security systems.

The world should feel like an operating industrial ecosystem.

### 5.3 Shared AI Architecture

Robots should use reusable AI systems. Do not implement every robot as a completely independent AI architecture.

Recommended shared systems:

- **Perception** — vision, hearing, environmental detection, suspicion tracking.
- **Navigation** — pathfinding, obstacle avoidance, movement, navigation between workstations.
- **Job System** — defines the robot's original purpose; manages work tasks; controls work routes; defines workstation interactions.
- **Security System** — identifies unauthorized activity; escalates security states; communicates with other units.
- **Combat System** — target selection, weapon behavior, positioning, combat reactions.
- **Damage System** — health and damage, component damage, destruction, loot generation.

Robot variants should be configurable through data rather than requiring duplicated AI code.

---

## 6. Security Response System

Every NEXUS facility has a local security state. Escalation should be based on player actions, detected threats, and facility conditions.

| State | Name | Behavior |
|---|---|---|
| 0 | NORMAL OPERATION | Robots perform their jobs. No active threat detection. The player may remain unnoticed. |
| 1 | ANOMALY DETECTED | Suspicious sounds or movements detected. HOUND investigates. WASP may inspect the area. Robots become more alert. |
| 2 | SECURITY WARNING | Player identified as an unauthorized intruder. SENTINEL issues warnings. Restricted doors may close. Security units begin searching. |
| 3 | SECURITY BREACH | Security units actively pursue the player. TURRETS become active. HOUND SECURITY engages. Production activities may be interrupted. |
| 4 | FACILITY LOCKDOWN | Reinforcements may be activated. Doors and access points are locked. Important production areas are secured. High-level security systems become active. |

**Important:** security escalation should not rely exclusively on spawning more enemies. Existing robots should react dynamically. Examples:

- MULE interrupts its transport route.
- TECHNICIAN repairs damaged machinery.
- HOUND searches for the player.
- SENTINEL guards important access points.
- GUARDIAN leaves its garage when activated.

Facilities should be able to return to normal operation after threats disappear, depending on their remaining functionality.

---

## 7. Gameplay Philosophy

### 7.1 Core Gameplay Loop

1. Exploration.
2. Resource discovery.
3. Reconnaissance of NEXUS facilities.
4. Risk assessment.
5. Infiltration.
6. Resource theft or extraction.
7. Escape.
8. Crafting and base progression.
9. Exploration of more dangerous facilities.

### 7.2 Multiple Ways to Deal With Robots

Combat should not be the only solution.

- **Destroy** — eliminate robots; recover components and materials.
- **Hack** — temporarily control compatible robots; manipulate their behavior; potentially gain access to their systems.
- **Distract** — create noises or other disturbances; redirect inspection and patrol units.
- **Sabotage** — disable machines; interrupt production; disable security systems.
- **Avoid** — use stealth; avoid detection; exploit patrol routes and blind spots.
- **Repurpose** — repair or capture selected machines; use them for transportation or other utility tasks.

Not every robot must support every interaction.

---

## 8. Resources and Loot

Robots and facilities are important sources of crafting materials. Resource distribution should make logical sense.

| Resource | Typical Sources | Usage |
|---|---|---|
| Scrap Metal | Industrial machines, robots | Basic crafting |
| Mechanical Parts | MINER, BUILDER, FORKLIFT | Tools and machines |
| Electronics | HOUND, WASP, TECHNICIAN | Electronic devices |
| Batteries | MULE, drones, vehicles | Energy |
| Circuits | Security robots, facilities | Advanced electronics |
| Servo Motors | Robotic joints and machines | Mechanical systems |
| Polymers | Industrial production | Equipment and components |
| Chemicals | Agriculture and industry | Processing and crafting |
| Advanced Components | Military and research systems | Endgame technology |

Loot must be consistent with the original function and physical construction of each robot.

- A mining machine should not randomly drop military electronics.
- A surveillance drone should not produce large amounts of structural metal.

---

## 9. World Regions

The world should contain distinct industrial environments. Each region has a specific purpose, visual identity, resource distribution, and robot population.

**MINING DISTRICT** — Open mining areas, excavation sites, ore processing, conveyor belts, heavy machinery.
Typical robots: MINER, MULE, HOUND, BUILDER.

**LOGISTICS DISTRICT** — Large warehouses, distribution centers, container yards, loading docks, automated transportation systems.
Typical robots: FORKLIFT, MULE, WASP, SENTINEL.

**AGRICULTURAL DISTRICT** — Greenhouses, automated farms, irrigation systems, food production, biomass processing.
Typical robots: HARVESTER, HOUND, TECHNICIAN.

**ENERGY DISTRICT** — Power plants, generators, battery storage, electrical substations, power distribution.
Typical robots: TECHNICIAN, SENTINEL, TURRET.

**SECURITY DISTRICT** — Military compounds, corporate security facilities, weapon storage, research protection, restricted installations.
Typical robots: HOUND SECURITY, GUARDIAN, ENFORCER, TURRET.

**RESEARCH DISTRICT** — Laboratories, prototype development, robotics research, experimental manufacturing, advanced technology.
Typical robots: OVERSEER, specialized prototypes, experimental units.

---

## 10. Visual Art Direction

This section is mandatory for all future asset generation and visual development.

### 10.1 Overall Style

The game uses a stylized low-poly / semi-low-poly 3D art style, combining:

- Stylized low-poly geometry.
- Hand-painted surfaces.
- Subtle PBR response.
- Strong and readable silhouettes.
- Slightly exaggerated but believable proportions.
- Clean real-time geometry.
- Isometric-friendly proportions.

The visual style should feel like a coherent stylized survival game, not a collection of unrelated AI-generated science-fiction illustrations.

Avoid excessive neon lighting.

### 10.2 Color Palette

Not defined yet. Colors are deferred to a later step and can be ignored for now.

### 10.3 Robot Design Rules

All NEXUS robots should share recognizable design language:

- Angular industrial panels.
- Visible mechanical joints.
- Functional sensor assemblies.
- Modular equipment.
- Exposed mechanical components where appropriate.
- Practical proportions.
- Consistent material treatment.
- Small corporate identification markings.

Different business divisions may have their own equipment and color variations. However, all robots must remain visually recognizable as NEXUS products.

### 10.4 Realism Level

The setting is near-future industrial robotics. Prefer plausible mechanical designs over fantasy technology.

Good references:

- Boston Dynamics-style quadruped robots.
- Autonomous industrial vehicles.
- Modern warehouse robotics.
- Agricultural automation.
- Commercial inspection drones.
- Military unmanned ground vehicles.

Avoid:

- Giant humanoid mechs as standard enemies.
- Oversized science-fiction weapons.
- Excessive glowing elements.
- Impossibly complicated mechanical structures.
- Generic futuristic armor.
- Unnecessary decorative details.

### 10.5 Isometric Readability

Every robot must be recognizable from the game's camera perspective.

Prioritize:

- Clear silhouettes.
- Distinct body shapes.
- Readable movement direction.
- Visible equipment.
- Strong separation between body parts.
- Appropriate scale relative to the player.

Important functional elements must remain visible from the isometric camera.

---

## 11. Asset Creation Guidelines

All assets should be designed for actual real-time 3D gameplay. Concept art is a reference, not a substitute for production assets.

When creating a new robot:

1. Define its industrial purpose.
2. Define its gameplay role.
3. Define its silhouette.
4. Define its mechanical construction.
5. Apply the NEXUS visual language.
6. Check its readability from the isometric camera.
7. Define its materials and textures.
8. Consider animations and interaction points.

Every robot should have a distinct silhouette and recognizable function.

Do not create multiple robots that only differ by weapon attachments unless they are intentionally variants of the same platform.

---

## 12. Technical Development Guidelines

Engine: Godot 4.6.

Robotic AI and world systems should be modular and data-driven. Recommended principles:

- Reusable AI components.
- Shared perception and navigation.
- Configurable robot definitions.
- Separate job and combat behavior.
- Independent facility security states.
- Modular damage and loot systems.
- Performance-conscious simulation.
- Clear separation between presentation and gameplay logic.

Avoid unnecessary complexity during early development. Build a small functional ecosystem first.

**The first playable prototype should include:**

- One mining facility.
- One MINER.
- One MULE.
- One HOUND.
- One WASP.
- One SENTINEL.
- One HOUND SECURITY.
- Basic resource extraction.
- A working alarm system.
- Basic player interaction and combat.

Only expand the roster after the core gameplay loop works.

---

## 13. Cursor AI Instructions

- Treat this document as the authoritative reference for NEXUS lore, robot design, and gameplay philosophy.
- Do not introduce contradictory worldbuilding without explicit user approval.
- Do not turn NEXUS into a conventional evil AI faction.
- Remember that NEXUS robots primarily execute industrial or security jobs.
- Prefer functional industrial robotics over generic science-fiction designs.
- Keep all robot concepts consistent with the defined art direction.
- Use the defined color palette as the default for NEXUS assets.
- Maintain isometric readability.
- Reuse existing AI systems and components wherever possible.
- Do not introduce unnecessary new gameplay systems when existing systems can be extended.
- Keep the implementation compatible with Godot 4.6.
- When proposing new enemies, always define their original industrial purpose, behavior, threat level, resource drops, and visual identity.
- When creating new facilities, define their production processes, resources, and robot population.
- Prioritize gameplay interactions beyond simply killing enemies.
- If a new idea conflicts with this document, explain the conflict and ask for clarification rather than silently changing the established direction.

---

## 14. Core Design Principles

- **WORLD** — A near-future world where autonomous corporate infrastructure continues operating after human civilization has collapsed.
- **FACTION** — NEXUS INDUSTRIES is a megacorporation whose robots continue executing their original instructions.
- **ENEMIES** — Robots are industrial machines, logistics systems, maintenance units, and security platforms first.
- **GAMEPLAY** — The player steals resources from operational facilities and interferes with autonomous production processes.
- **AI** — Robots should have believable jobs, routines, perception, and security responses.
- **PROGRESSION** — Players gradually move from scavenging civilian industrial facilities to infiltrating heavily protected corporate installations.
- **VISUALS** — Stylized low-poly 3D, hand-painted surfaces, muted military-industrial colors, believable near-future machinery, and clear isometric silhouettes.
- **TECHNOLOGY** — Godot 4.6, modular systems, reusable AI, and data-driven robot definitions.

### Final Design Statement

NEXUS INDUSTRIES is not an army of robots waiting to fight the player.

It is an autonomous industrial civilization that continues to operate without humans.

Every machine has a purpose. Every facility has a production process. Every resource belongs to an automated supply chain.

The player survives by entering this system, taking what they need, and dealing with the consequences.

**NEXUS keeps working. The player keeps interfering.**
