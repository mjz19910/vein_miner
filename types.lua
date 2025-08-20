---@class InvRef
---@field is_empty fun(self: InvRef, listname: string): boolean
---@field get_size fun(self: InvRef, listname: string): integer
---@field set_size fun(self: InvRef, listname: string, size: integer): boolean
---@field get_width fun(self: InvRef, listname: string): integer
---@field set_width fun(self: InvRef, listname: string, width: integer): boolean
---@field get_stack fun(self: InvRef, listname: string, index: integer): ItemStack
---@field set_stack fun(self: InvRef, listname: string, index: integer, stack: ItemStack): boolean
---@field get_list fun(self: InvRef, listname: string): ItemStack[]|nil
---@field set_list fun(self: InvRef, listname: string, list: ItemStack[]): nil
---@field get_lists fun(self: InvRef): table<string, ItemStack[]>
---@field set_lists fun(self: InvRef, lists: table<string, ItemStack[]>): nil
---@field add_item fun(self: InvRef, listname: string, item: ItemStack|string|table|nil): ItemStack
---@field remove_item fun(self: InvRef, listname: string, item: ItemStack|string|table|nil, match_meta?: boolean): ItemStack
---@field room_for_item fun(self: InvRef, listname: string, item: ItemStack|string|table|nil): boolean
---@field contains_item fun(self: InvRef, listname: string, item: ItemStack|string|table|nil, match_meta?: boolean): boolean
---@field get_location fun(self: InvRef): InvLocation
local inv = {}

---@alias InvLocation InvLocationPlayer|InvLocationNode|InvLocationDetached|InvLocationUndefined

---@class InvLocationPlayer
---@field type '"player"'
---@field name string           -- player name

---@class InvLocationNode
---@field type '"node"'
---@field pos Vector            -- node position {x=, y=, z=}

---@class InvLocationDetached
---@field type '"detached"'
---@field name string           -- detached inventory name

---@class InvLocationUndefined
---@field type '"undefined"'

---@class ItemStackTable
---@field name string
---@field count integer
---@field wear integer
---@field metadata string
---@field meta table<string, string>

---@class ItemStack
---@field is_empty fun(self: ItemStack): boolean
---@field get_name fun(self: ItemStack): string
---@field set_name fun(self: ItemStack, name: string): nil
---@field get_count fun(self: ItemStack): integer
---@field set_count fun(self: ItemStack, count: integer): nil
---@field get_wear fun(self: ItemStack): integer
---@field set_wear fun(self: ItemStack, wear: integer)
---@field get_meta fun(self: ItemStack): ItemStackMetaRef
---@field clear fun(self: ItemStack): nil
---@field replace fun(self: ItemStack, item: ItemStack|string|table|nil): nil
---@field to_string fun(self: ItemStack): string
---@field to_table fun(self: ItemStack): ItemStackTable|nil
---@field get_stack_max fun(self: ItemStack): integer
---@field get_free_space fun(self: ItemStack): integer
---@field is_known fun(self: ItemStack): boolean
---@field get_definition fun(self: ItemStack): ItemDefinition
---@field get_tool_capabilities fun(self: ItemStack): ToolCaps
---@field add_wear fun(self: ItemStack, amount: integer): nil
---@field add_item fun(self: ItemStack, item: ItemStack|string|table|nil): ItemStack
---@field take_item fun(self: ItemStack, count: integer|nil): ItemStack
---@field peek_item fun(self: ItemStack, count: integer|nil): ItemStack
local stack = {}

---@class ItemDefinition
---@field name string
---@field description string
---@field short_description string|nil
---@field groups table<string, integer>
---@field inventory_image string
---@field wield_image string
---@field wield_scale number[]|nil
---@field stack_max integer
---@field liquids_pointable boolean|nil
---@field light_source integer|nil
---@field range number|nil
---@field tool_capabilities ToolCaps|nil
---@field damage_groups table<string, number>|nil
---@field sounds table<string, any>|nil
---@field after_use AfterUseCallback|nil
---@field on_use OnUseCallback|nil
---@field on_place OnPlaceCallback|nil
---@field on_drop OnDropCallback|nil
---@field node_placement_prediction string|nil

---@alias AfterUseCallback fun(itemstack: ItemStack, user: ObjectRef, node: MapNode): ItemStack|nil
---@alias OnUseCallback fun(itemstack: ItemStack, user: ObjectRef, pointed_thing: PointedThing): ItemStack|nil
---@alias OnPlaceCallback fun(itemstack: ItemStack, placer: ObjectRef, pointed_thing: PointedThing): ItemStack|nil
---@alias OnDropCallback fun(itemstack: ItemStack, dropper: ObjectRef, pos: Vector): ItemStack|nil

---@class PointedThingNothing
---@field type '"nothing"'

---@class PointedThingNode
---@field type '"node"'
---@field under Vector
---@field above Vector

---@class PointedThingObject
---@field type '"object"'
---@field under Vector
---@field above Vector
---@field ref ObjectRef

---@alias PointedThing PointedThingNothing | PointedThingNode | PointedThingObject

---@class ToolCaps
---@field full_punch_interval number
---@field max_drop_level integer
---@field groupcaps table<string, ToolGroupCap>
---@field damage_groups table<string, number>

---@class ToolGroupCap
---@field maxlevel integer|nil
---@field uses integer|nil
---@field times table<number, number>|nil -- map from rating (int) to time (float)

---@class ToolCapabilities
---@field full_punch_interval number|nil
---@field max_drop_level integer|nil
---@field punch_attack_uses integer|nil
---@field groupcaps table<string, ToolGroupCap>|nil
---@field damage_groups table<string, integer>|nil

---@alias WearBarBlendMode '"constant"' | '"linear"' | '"smooth"'

---@class ARGBColor
---@field a integer|nil @Alpha channel (0-255), defaults to 255 if omitted
---@field r integer @Red channel (0-255), required
---@field g integer @Green channel (0-255), required
---@field b integer @Blue channel (0-255), required

---@alias ColorParam ARGBColor|integer|string
-- ColorParam can be:
-- - a table with `a`, `r`, `g`, `b` integer fields (ARGBColor),
-- - a integer representing a packed color
-- - or a string color name or hex string.

---@class WearBarParams
---@field color_stops table<number, ColorParam> -- keys 0..1, values color specs
---@field blend WearBarBlendMode|nil
--- from read_wear_bar_params

---@class ItemStackMetaRef : MetaRef
---@field set_tool_capabilities fun(self: ItemStackMetaRef, caps: ToolCapabilities|nil)
---@field set_wear_bar_params fun(self: ItemStackMetaRef, params: WearBarParams|string|nil)

---@class Player: ObjectRef
local player = {}

---@class PlayerControl
---@field up boolean
---@field down boolean
---@field left boolean
---@field right boolean
---@field jump boolean
---@field aux1 boolean
---@field sneak boolean
---@field dig boolean
---@field place boolean
---@field movement_x number
---@field movement_y number
---@field LMB boolean
---@field RMB boolean
---@field zoom boolean
local player_control = player.get_player_control()

---@class Chunk
---@field area VoxelArea
---@field start_list Vector[]
local chunk = {}

---@class SimpleSoundSpec
---@field name string|string[] Sound name or list of names to choose from
---@field gain number|nil Default gain (volume multiplier)
---@field fade number|nil
---@field pitch number|nil Default pitch multiplier

---@class ServerSoundParams
---@field gain number|nil Override gain
---@field fade number|nil Override fade
---@field pitch number|nil Override pitch
---@field loop boolean|nil
---@field to_player string|nil
---@field pos Vector|nil
---@field max_hear_distance number|nil
---@field object ObjectRef|nil
---@field exclude_player string|nil

---@class NodeHash: number
---@class ContentId: number

---@class CoreModApi
---@field get_voxel_manip fun(): VoxelManip
---@field set_node fun(pos: Vector, node: MapNode)
---@field get_node fun(pos: Vector): MapNode
---@field get_node_or_nil fun(pos: Vector): MapNode | nil
---@field sound_play fun(spec: string|SimpleSoundSpec, params: ServerSoundParams|nil, ephemeral: boolean|nil)
---@field get_connected_players fun(): Player[]
---
---@field add_particle fun(params: ParticleParameters): boolean
---@field add_particlespawner fun(params: ParticleSpawnerParameters): integer
---@field delete_particlespawner fun(id: integer, playername?: string)
---
---@field get_modpath fun(mod: string): string
---
---@field get_player_by_name fun(name: string): Player | nil
---
---@field get_current_modname fun(): string
---
---@field registered_nodes table<string, RegNode>
---@field hash_node_position fun(pos: Vector): NodeHash
---@field get_position_from_hash fun(hash: NodeHash): Vector
---@field get_name_from_content_id fun(id: ContentId): string
---@field chat_send_player fun(name: string, message: string)
---@type CoreModApi
core = {}
---@type CoreModApi
minetest = {}
---@class FixedNodeBox
---@field type '"fixed"'
---@field fixed number[]
local fixed_node_box = {}

---@alias SoundDef table<string, SoundParams>
local sound_def = {}

---@class SoundParams
---@field name string
---@field gain number
local sound_params = {
	name = "default_place_node_hard",
	gain = 1,
}

---@alias ParamType2 '"facedir"' | '"4dir"'
---@alias DrawType '"nodebox"' | '"liquid"' | '"airlike"' | '"plantlike"' | '"allfaces_optional"'

---@class RegNode
---@field type '"node"'
---@field name string
---@field mod_origin string
---@field tiles TileDef[] | nil
---@field selection_box FixedNodeBox | nil
---@field light_source number | nil
---@field is_ground_content boolean | nil
---@field sounds SoundDef | nil
---@field allow_metadata_inventory_put fun(pos: Vector, listname: string, index: number, stack: ItemStack, player: Player | nil): nil
---@field groups table<string, integer>
---@field node_box FixedNodeBox | nil
---@field paramtype2 ParamType2 | nil
---@field drawtype DrawType | nil
---@field special_tiles TileDef[]
---@field walkable boolean
---@field buildable_to boolean
---@field floodable boolean
---@field air_equivalent boolean
---@field liquidtype '"source"' | '"flowing"'
---@type RegNode
local reg_node = {}

---@type VoxelManip
local vm = core.get_voxel_manip()

---@class VoxelManip
---@field read_from_map fun(self:VoxelManip, p1:Vector, p2:Vector): Vector, Vector		Reads region from map; returns min and max edges
---@field initialize fun(self:VoxelManip, p1:Vector, p2:Vector, fill_node?: table): Vector, Vector	Initializes region optionally filling with node; returns min and max edges
---@field get_data fun(self:VoxelManip, buffer?: table): ContentId[]	Returns node content IDs; optional buffer table
---@field set_data fun(self:VoxelManip, data: ContentId[]) Sets node content IDs
---@field write_to_map fun(self:VoxelManip, update_light?: boolean) Writes changes back to map; optionally updates lighting (default true)
---@field get_node_at fun(self:VoxelManip, pos:Vector): table Gets node at position
---@field set_node_at fun(self:VoxelManip, pos:Vector, node: table): boolean Sets node at position; returns success
---@field update_liquids fun(self:VoxelManip) Updates flowing liquids
---@field calc_lighting fun(self:VoxelManip, pmin?: Vector, pmax?: Vector, propagate_shadow?: boolean)  Calculates lighting (mapgen VM only)
---@field set_lighting fun(self:VoxelManip, light_table: table, pmin?: Vector, pmax?: Vector)  Sets lighting (mapgen VM only)
---@field get_light_data fun(self:VoxelManip, buffer?: table): integer[] Gets light data; optional buffer
---@field set_light_data fun(self:VoxelManip, data: integer[]) Sets light data
---@field get_param2_data fun(self:VoxelManip, buffer?: table): integer[] Gets param2 data; optional buffer
---@field set_param2_data fun(self:VoxelManip, data: integer[]) Sets param2 data
---@field update_map fun(self:VoxelManip) Updates the map (no-op)
---@field was_modified fun(self:VoxelManip): boolean Returns whether data was modified
---@field get_emerged_area fun(self:VoxelManip): Vector, Vector Returns min and max edges of emerged area
---@field close fun(self:VoxelManip) Disposes object (not allowed on mapgen VMs)
local vm = {}

---@class Vector
---@field x number
---@field y number
---@field z number
local vec = {}

---@class VectorModule
---@field metatable table
---@field new fun(x: number, y: number, z: number): Vector
---@field zero fun(): Vector
---@field copy fun(v: Vector): Vector
---@field from_string fun(s: string, init?: number): Vector | nil, number | nil
---@field to_string fun(v: Vector): string
---@field equals fun(a: Vector, b: Vector): boolean
---@field length fun(v: Vector): number
---@field normalize fun(v: Vector): Vector
---@field floor fun(v: Vector): Vector
---@field round fun(v: Vector): Vector
---@field ceil fun(v: Vector): Vector
---@field sign fun(v: Vector, tolerance?: number): Vector
---@field abs fun(v: Vector): Vector
---@field apply fun(v: Vector, func: fun(x: number, ...: any): number): Vector
---@field combine fun(a: Vector, b: Vector, func: fun(a: number, b: number): number): Vector
---@field distance fun(a: Vector, b: Vector): number
---@field direction fun(pos1: Vector, pos2: Vector): Vector
---@field angle fun(a: Vector, b: Vector): number
---@field dot fun(a: Vector, b: Vector): number
---@field cross fun(a: Vector, b: Vector): Vector
---@field add fun(a: Vector, b: Vector | number): Vector
---@field subtract fun(a: Vector, b: Vector | number): Vector
---@field multiply fun(a: Vector, b: Vector | number): Vector
---@field divide fun(a: Vector, b: Vector | number): Vector
---@field offset fun(v: Vector, x: number, y: number, z: number): Vector
---@field sort fun(a: Vector, b: Vector): Vector, Vector
---@field check fun(v: any): boolean
---@field rotate_around_axis fun(v: Vector, axis: Vector, angle: number): Vector
---@field rotate fun(v: Vector, rot: Vector): Vector
---@field dir_to_rotation fun(forward: Vector, up?: Vector): Vector
---@field in_area fun(pos: Vector, min: Vector, max: Vector): boolean
---@field random_direction fun(): Vector
---@field random_in_area fun(min: Vector, max: Vector): Vector
---@field zero fun(): Vector

---@class PlayerConfig
---@field mode '"small"'|'"large"'
---@field miny number
---@field maxy number
---@field last_maxy number|nil
---@field blocks_per_tick number
---@field floor_place_limit integer|nil
---@type PlayerConfig
local config_data = {}

---@type PlayerConfigManager
local player_config_mgr = {}

---@class ObjectRef
---
---## Lifecycle
---@field remove fun(self:ObjectRef)
---@field is_valid fun(self:ObjectRef): boolean
---@field get_guid fun(self:ObjectRef): string
---
---## Position & Movement
---@field get_pos fun(self:ObjectRef): Vector
---@field set_pos fun(self:ObjectRef, pos:Vector)
---@field add_pos fun(self:ObjectRef, pos:Vector)
---@field move_to fun(self:ObjectRef, pos:Vector, continuous?:boolean)
---@field get_velocity fun(self:ObjectRef): Vector
---@field set_velocity fun(self:ObjectRef, vel:Vector)
---@field add_velocity fun(self:ObjectRef, vel:Vector)
---@field get_acceleration fun(self:ObjectRef): Vector
---@field set_acceleration fun(self:ObjectRef, acc:Vector)
---@field get_rotation fun(self:ObjectRef): Vector
---@field set_rotation fun(self:ObjectRef, rot:Vector)
---@field get_yaw fun(self:ObjectRef): number
---@field set_yaw fun(self:ObjectRef, yaw:number)
---
---## Interaction
---@field punch fun(self:ObjectRef, puncher:ObjectRef, time_from_last_punch:number, tool_capabilities:ToolCaps, dir:Vector)
---@field right_click fun(self:ObjectRef, clicker:ObjectRef)
---
---## Health
---@field set_hp fun(self:ObjectRef, hp:number, reason?:table)
---@field get_hp fun(self:ObjectRef): number
---
---## Inventory
---@field get_inventory fun(self:ObjectRef): InvRef
---@field get_wield_list fun(self:ObjectRef): string
---@field get_wield_index fun(self:ObjectRef): number
---@field get_wielded_item fun(self:ObjectRef): ItemStack
---@field set_wielded_item fun(self:ObjectRef, item:ItemStack | string)
---
---## Armor
---@field set_armor_groups fun(self:ObjectRef, groups:table<string,integer>)
---@field get_armor_groups fun(self:ObjectRef): table<string,integer>
---
---## Physics
---@field set_physics_override fun(self:ObjectRef, override_table:PhysicsOverride)
---@field get_physics_override fun(self:ObjectRef): PhysicsOverride
---
---## Animation
---@field set_animation fun(self:ObjectRef, frame_range?:Vector, frame_speed?:number, frame_blend?:number, frame_loop?:boolean)
---@field set_animation_frame_speed fun(self:ObjectRef, frame_speed:number)
---@field get_animation fun(self:ObjectRef): table
---
---## Bones
---@field set_bone_position fun(self:ObjectRef, bone:string, position:Vector, rotation:Vector)
---@field get_bone_position fun(self:ObjectRef, bone:string): Vector, Vector
---@field set_bone_override fun(self:ObjectRef, bone:string)
---@field get_bone_override fun(self:ObjectRef, bone:string): any
---@field get_bone_overrides fun(self:ObjectRef): any
---
---## Attachment
---@field set_attach fun(self:ObjectRef, parent:ObjectRef, bone?:string, position?:Vector, rotation?:Vector)
---@field get_attach fun(self:ObjectRef): table
---@field get_children fun(self:ObjectRef): ObjectRef[]
---@field set_detach fun(self:ObjectRef)
---
---## Entity Properties
---@field get_properties fun(self:ObjectRef): table
---@field set_properties fun(self:ObjectRef, props:table)
---
---## Observers
---@field set_observers fun(self:ObjectRef, observers:table)
---@field get_observers fun(self:ObjectRef): table
---@field get_effective_observers fun(self:ObjectRef): table
---
---## Identification
---@field is_player fun(self:ObjectRef): boolean
---
---## Appearance
---@field set_texture_mod fun(self:ObjectRef, mod:string)
---@field get_texture_mod fun(self:ObjectRef): string
---@field set_sprite fun(self:ObjectRef, start_frame:number, num_frames:number, framelength:number, select_horiz_by_yawpitch?:boolean)
---
---## Player Specific
---@field get_player_name fun(self:ObjectRef): string
---@field get_fov fun(self:ObjectRef): number, boolean|nil, number|nil
---@field set_fov fun(self:ObjectRef, degrees:number, is_multiplier?:boolean, transition_time?:number)
---@field get_look_dir fun(self:ObjectRef): Vector
---@field get_look_vertical fun(self:ObjectRef): number
---@field set_look_vertical fun(self:ObjectRef, radians:number)
---@field get_look_horizontal fun(self:ObjectRef): number
---@field set_look_horizontal fun(self:ObjectRef, radians:number)
---@field set_breath fun(self:ObjectRef, breath:number)
---@field get_breath fun(self:ObjectRef): number
---@field get_meta fun(self:ObjectRef): MetaRef
---@field set_inventory_formspec fun(self:ObjectRef, formspec:string)
---@field get_inventory_formspec fun(self:ObjectRef): string
---@field set_formspec_prepend fun(self:ObjectRef, formspec:string)
---@field get_formspec_prepend fun(self:ObjectRef): string
---@field get_player_control fun(self:ObjectRef): PlayerControl
---@field get_player_control_bits fun(self:ObjectRef): integer
---
---## HUD
---@field hud_add fun(self:ObjectRef, form:HUDDef): integer
---@field hud_remove fun(self:ObjectRef, id:integer)
---@field hud_change fun(self:ObjectRef, id:integer, stat:string, data:any)
---@field hud_get_next_id fun(self:ObjectRef): integer
---@field hud_get fun(self:ObjectRef, id:integer): HUDDef
---@field hud_get_all fun(self:ObjectRef): table<integer,HUDDef>
---@field hud_set_flags fun(self:ObjectRef, flags:HUDFlags)
---@field hud_get_flags fun(self:ObjectRef): HUDFlags
---@field hud_set_hotbar_itemcount fun(self:ObjectRef, count:integer)
---@field hud_get_hotbar_itemcount fun(self:ObjectRef): integer
---@field hud_set_hotbar_image fun(self:ObjectRef, name:string)
---@field hud_get_hotbar_image fun(self:ObjectRef): string
---@field hud_set_hotbar_selected_image fun(self:ObjectRef, name:string)
---@field hud_get_hotbar_selected_image fun(self:ObjectRef): string
---
---## Environment Visuals
---@field set_sky fun(self:ObjectRef, sky_parameters:SkyParams)
---@field get_sky fun(self:ObjectRef, as_table?:boolean): table|string
---@field set_sun fun(self:ObjectRef, sun_parameters:SunParams)
---@field get_sun fun(self:ObjectRef): SunParams
---@field set_moon fun(self:ObjectRef, moon_parameters:MoonParams)
---@field get_moon fun(self:ObjectRef): MoonParams
---@field set_stars fun(self:ObjectRef, star_parameters:StarParams)
---@field get_stars fun(self:ObjectRef): StarParams
---@field set_clouds fun(self:ObjectRef, cloud_parameters:CloudParams)
---@field get_clouds fun(self:ObjectRef): CloudParams
---@field override_day_night_ratio fun(self:ObjectRef, ratio:number)
---@field get_day_night_ratio fun(self:ObjectRef): number
---@field set_local_animation fun(self:ObjectRef, idle:table, walk:table, dig:table, walk_while_dig:table, frame_speed:number)
---@field get_local_animation fun(self:ObjectRef): table
---@field set_eye_offset fun(self:ObjectRef, firstperson:Vector, thirdperson:Vector, thirdperson_front:Vector)
---@field get_eye_offset fun(self:ObjectRef): Vector, Vector, Vector
---@field set_camera fun(self:ObjectRef, params:CameraParams)
---@field get_camera fun(self:ObjectRef): CameraParams
---@field set_nametag_attributes fun(self:ObjectRef, attributes:table)
---@field get_nametag_attributes fun(self:ObjectRef): table
---@field send_mapblock fun(self:ObjectRef, pos:Vector)
---@field set_minimap_modes fun(self:ObjectRef, modes:table, wanted_mode:integer)
---@field set_lighting fun(self:ObjectRef, lighting:LightingParams)
---@field get_lighting fun(self:ObjectRef): LightingParams
---@field respawn fun(self:ObjectRef)
---@field set_flags fun(self:ObjectRef, flags:EntityFlags)
---@field get_flags fun(self:ObjectRef): EntityFlags

---@type ObjectRef
local ObjectRef = {}

---@type ToolCaps
local tool_caps = {}

---@class PhysicsOverride
---@field speed number|nil
---@field jump number|nil
---@field gravity number|nil
---@field sneak boolean|nil
---@field sneak_glitch boolean|nil
---@field new_move boolean|nil
---@field noclip boolean|nil

---@class MetaRef
---@field get_string fun(self: MetaRef, key: string): string
---@field set_string fun(self: MetaRef, key: string, value: string): void
---@field get_int fun(self: MetaRef, key: string): integer
---@field set_int fun(self: MetaRef, key: string, value: integer): void
---@field get_float fun(self: MetaRef, key: string): number
---@field set_float fun(self: MetaRef, key: string, value: number): void
---@field contains fun(self: MetaRef, key: string): boolean
---@field to_table fun(self: MetaRef): table
---@field from_table fun(self: MetaRef, tbl: table): void
---@field serialize fun(self: MetaRef): string
---@field deserialize fun(self: MetaRef, data: string): void
---@field get_inventory fun(self: MetaRef): InventoryRef

---@class InventoryRef
---@field get_size fun(self: InventoryRef): integer
---@field get_width fun(self: InventoryRef): integer
---@field get_stack fun(self: InventoryRef, listname: string, index: integer): ItemStack
---@field set_stack fun(self: InventoryRef, listname: string, index: integer, stack: ItemStack): boolean
---@field add_item fun(self: InventoryRef, listname: string, stack: ItemStack | string): ItemStack
---@field remove_item fun(self: InventoryRef, listname: string, stack: ItemStack | string): ItemStack
---@field get_list_name fun(self: InventoryRef, index: integer): string
---@field get_lists fun(self: InventoryRef): table<string, integer> -- map of listname to size
---@field contains_item fun(self: InventoryRef, listname: string, stack: ItemStack | string): boolean
---@field room_for_item fun(self: InventoryRef, listname: string, stack: ItemStack | string): boolean
---@field is_empty fun(self: InventoryRef, listname: string): boolean
---@field set_list fun(self: InventoryRef, listname: string, list: ItemStack[]): boolean
---@field get_stack_max fun(self: InventoryRef): integer

---@class HUDDef
---@field hud_elem_type string
---@field position Vector|nil
---@field name string|nil
---@field text string|nil
---@field number integer|nil

---@class HUDFlags
---@field hotbar boolean|nil
---@field healthbar boolean|nil
---@field crosshair boolean|nil
---@field wielditem boolean|nil
---@field breathbar boolean|nil
---@field minimap boolean|nil
---@field minimap_radar boolean|nil

---@class SkyParams
---@field base_color ColorSpec|nil
---@field type string|nil
---@field textures string[]|nil
---@field clouds boolean|nil

---@class SunParams
---@field visible boolean|nil
---@field texture string|nil
---@field sunrise string|nil
---@field sunrise_visible boolean|nil

---@class MoonParams
---@field visible boolean|nil
---@field texture string|nil

---@class StarParams
---@field visible boolean|nil
---@field count number|nil
---@field star_color ColorSpec|nil

---@class CloudParams
---@field density number|nil
---@field color ColorSpec|nil
---@field ambient ColorSpec|nil
---@field height number|nil
---@field thickness number|nil
---@field speed Vector|nil

---@class CameraParams
---@field mode integer|nil
---@field view_offset Vector|nil
---@field zoom number|nil

---@class LightingParams
---@field shadows boolean|nil
---@field light_source number|nil
---@field day_light number|nil
---@field night_light number|nil

---@class EntityFlags
---@field collide_with_objects boolean|nil
---@field pointable boolean|nil
---@field immortal boolean|nil

---@alias ColorSpec string | ColorSpecTable

---@class ColorSpecTable
---@field a number|nil
---@field r number
---@field g number
---@field b number

---@class RGBAColor
---@field a number
---@field r number
---@field g number
---@field b number

---@class ParticleTextureAnimation
---@field length integer
---@field frame_length integer
---@field frames integer[]
---@field blend string|nil

---@class ParticleTexture
---@field string string
---@field animated boolean
---@field animation ParticleTextureAnimation|nil
---@field blendmode integer|nil
---@field alpha any|nil
---@field scale any|nil

---@class Range
---@generic T
---@field min T
---@field max T

---@class CommonParticleParams
---@field collisiondetection boolean
---@field collision_removal boolean
---@field object_collision boolean
---@field vertical boolean
---@field texture ServerParticleTexture
---@field animation TileAnimationParams
---@field glow integer
---@field node MapNode
---@field node_tile integer

---@class ParticleParameters : CommonParticleParams
---@field pos Vector
---@field vel Vector
---@field acc Vector
---@field drag Vector
---@field size number
---@field expirationtime number
---@field bounce Range<number>
---@field jitter Range<Vector>

---@class ParticleSpawnerParameters : CommonParticleParams
---@field amount integer
---@field time number
---@field texpool ServerParticleTexture[]  -- array of textures

---@class ServerParticleTexture
---@field string string           -- texture name or path
---@field animated boolean
---@field animation TileAnimationParams
---@field blendmode integer|nil
---@field alpha any|nil
---@field scale any|nil

---@class MeseconPortStates
---@field a boolean
---@field b boolean
---@field c boolean
---@field d boolean

---@alias TileDef string | TileDefTable

---@class TileDefTable
---@field name string
---@field tileable_vertical boolean

---@class TileAnimationParams
---@field type '"vertical_frames"'
---@field aspect_w integer
---@field aspect_h integer
---@field length number

---@class NumRange
---@field min number
---@field max number

---@class VoxelArea
---@field MinEdge Vector      Minimum coordinate of the area
---@field MaxEdge Vector      Maximum coordinate of the area
---@field ystride integer     Size of one Y-level in array indexing
---@field zstride integer     Size of one Z-level in array indexing
---@field index fun(self:VoxelArea, x:integer, y:integer, z:integer): integer
---@field indexp fun(self:VoxelArea, pos:Vector): integer
---@field position fun(self:VoxelArea, index:integer): Vector
---@field contains fun(self:VoxelArea, x:integer, y:integer, z:integer): boolean
---@field containsp fun(self:VoxelArea, pos:Vector): boolean
---@field new fun(self: VoxelArea, init: VoxelArea|nil): VoxelArea

