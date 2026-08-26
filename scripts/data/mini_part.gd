extends Resource
class_name MiniPart

enum Slot { HEAD, TORSO, LEGS, WEAPON }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
enum Race { NONE, IRONCLAD, SKARRGOR, WHISPERWOOD }
enum DamageType { PHYSICAL, MAGICAL }

@export var part_id: String
@export var display_name: String
@export var slot: Slot
@export var rarity: Rarity
@export var race: Race = Race.NONE
@export var unit_type_name: String = ""

## Which damage a unit assembled with this part's weapon deals. Only
## meaningful on WEAPON parts, but stamped on every part of a unit type for
## simplicity since assembly requires all 4 parts to match anyway.
@export var damage_type: DamageType = DamageType.PHYSICAL

## Passive ability carried by this unit type, if any (Uncommon rarity and
## above only). Empty string means no passive.
@export var passive_id: String = ""
@export var passive_name: String = ""
@export var passive_description: String = ""

## Combat profile for this unit type (same value stamped on all 4 parts,
## same reasoning as damage_type: assembly requires all parts to match
## anyway, so any part can carry the unit-level combat stats).
@export var attack_range: float = 40.0 ## melee ~40, ranged ~220
@export var attack_interval: float = 1.2 ## seconds between regular attacks

@export_group("Stats")
@export var might: int = 0 ## physical attack power
@export var prowess: int = 0 ## magical attack power
@export var armor: int = 0 ## physical damage mitigation
@export var resistance: int = 0 ## magical damage mitigation
@export var health: int = 0
@export var speed: float = 0.0 ## movement speed
@export var dodge_chance: float = 0.0 ## percent chance to fully avoid an attack

@export_group("Visuals")
@export var sprite: Texture2D
@export var tint: Color = Color.WHITE

static func rarity_name(r: Rarity) -> String:
	match r:
		Rarity.COMMON: return "Common"
		Rarity.UNCOMMON: return "Uncommon"
		Rarity.RARE: return "Rare"
		Rarity.EPIC: return "Epic"
		Rarity.LEGENDARY: return "Legendary"
	return "Unknown"

static func rarity_color(r: Rarity) -> Color:
	match r:
		Rarity.COMMON: return Color("b0b0b0")
		Rarity.UNCOMMON: return Color("5fd97a")
		Rarity.RARE: return Color("4da3ff")
		Rarity.EPIC: return Color("b24dff")
		Rarity.LEGENDARY: return Color("ffb84d")
	return Color.WHITE

static func race_name(r: Race) -> String:
	match r:
		Race.NONE: return "Neutral"
		Race.IRONCLAD: return "Ironclad"
		Race.SKARRGOR: return "Skarrgor"
		Race.WHISPERWOOD: return "Whisperwood"
	return "Unknown"

static func slot_name(s: Slot) -> String:
	match s:
		Slot.HEAD: return "Head"
		Slot.TORSO: return "Torso"
		Slot.LEGS: return "Legs"
		Slot.WEAPON: return "Weapon"
	return "Unknown"

static func damage_type_name(d: DamageType) -> String:
	match d:
		DamageType.PHYSICAL: return "Physical"
		DamageType.MAGICAL: return "Magical"
	return "Unknown"

## Two parts belong to the same buildable set if they share a race and unit
## type. Used to enforce that a unit can only be assembled from matching parts.
func matches_set(other: MiniPart) -> bool:
	return race == other.race and unit_type_name == other.unit_type_name
