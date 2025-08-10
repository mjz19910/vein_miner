---@class InvRef
---@field get_size fun(self: InvRef, listname: string): integer
---@field set_size fun(self: InvRef, listname: string, size: integer)
---@field get_width fun(self: InvRef, listname: string): integer
---@field set_width fun(self: InvRef, listname: string, width: integer)
---@field get_stack fun(self: InvRef, listname: string, index: integer): ItemStack
---@field set_stack fun(self: InvRef, listname: string, index: integer, stack: ItemStack)
---@field add_item fun(self: InvRef, listname: string, stack: ItemStack): ItemStack|nil
---@field remove_item fun(self: InvRef, listname: string, stack: ItemStack): ItemStack|nil
---@field room_for_item fun(self: InvRef, listname: string, stack: ItemStack): boolean
---@field contains_item fun(self: InvRef, listname: string, stack: ItemStack): boolean
---@field get_list_names fun(self: InvRef): string[]
---@field set_location fun(self: InvRef, location: string)
local inv = {}

---@class MetaDataRef
---@field get_string fun(self: MetaDataRef, key: string): string
---@field set_string fun(self: MetaDataRef, key: string, value: string)
---@field get_int fun(self: MetaDataRef, key: string): integer
---@field set_int fun(self: MetaDataRef, key: string, value: integer)
---@field get_float fun(self: MetaDataRef, key: string): number
---@field set_float fun(self: MetaDataRef, key: string, value: number)
---@field to_table fun(self: MetaDataRef): table
---@field from_table fun(self: MetaDataRef, table: table)
---@field get_inventory fun(self: MetaDataRef): InvRef
---@field set_inventory fun(self: MetaDataRef, inv: InvRef)
local meta = {}

---@class ItemStack
---@field get_count fun(self: ItemStack): integer
---@field get_name fun(self: ItemStack): string
---@field take_item fun(self: ItemStack, count: integer): ItemStack
---@field add_item fun(self: ItemStack, stack: ItemStack|string): ItemStack
---@field get_wear fun(self: ItemStack): integer
---@field set_wear fun(self: ItemStack, wear: integer)
---@field get_meta fun(self: ItemStack): MetaDataRef
---@field to_string fun(self: ItemStack): string
local stack = {}

---@class Player
---@field get_player_name fun(self: Player): string
---@field get_pos fun(self: Player): vector
---@field hud_add fun(self: Player, params: table): integer
---@field hud_remove fun(self: Player, id: integer)
---@field hud_change fun(self: Player, id: integer, params: table)
---@field hud_get fun(self: Player, id: integer): table
---@field get_wielded_item fun(self: Player): ItemStack
---@field set_wielded_item fun(self: Player, item: ItemStack|string)
---@field is_player fun(self: any): boolean
---@field get_player_control fun(self: Player): PlayerControl
local player = {}

---@class PlayerControl
---@field sneak boolean
local player_control = player.get_player_control()

---@class Chunk
---@field area VoxelArea
---@field start_list Vector[]
local chunk = {}

---@class VeinMinerConfig
---@field cardinal_dirs Vector[]
---@field MINE_ONLY_CUR_SET string[]
---@field MINE_ONLY_GROUPS table<string, string[]>
---@field VEC_DIRS Vector[]
---@field MAX_MINED_NODES number
local config = {}

---@class VeinMinerGlobal
---@field CFG VeinMinerConfig
---@field utils VeinMinerUtils
---@field l_utils VienMinerLateUtils
---@field player_config PlayerConfigManager
---@field mine_only_cur_set table<string, boolean>
---@field mine_only_group_sets table<string, string>
local vein_miner = {}
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

---@class LuantiCore
---@field get_voxel_manip fun(): VoxelManip
---@field set_node fun(pos: Vector, node: Node)
---@field get_node fun(pos: Vector): Node
---@field get_node_or_nil fun(pos: Vector): Node | nil
---@field sound_play fun(spec: string|SimpleSoundSpec, params: ServerSoundParams|nil, ephemeral: boolean|nil)
---@field get_connected_players fun(): Player[]
core = {}
local vm = core.get_voxel_manip()

---@class VoxelManip
---@field read_from_map fun(self:VoxelManip, p1:Vector, p2:Vector): Vector, Vector		Reads region from map; returns min and max edges
---@field initialize fun(self:VoxelManip, p1:Vector, p2:Vector, fill_node?: table): Vector, Vector	Initializes region optionally filling with node; returns min and max edges
---@field get_data fun(self:VoxelManip, buffer?: table): integer[]	Returns node content IDs; optional buffer table
---@field set_data fun(self:VoxelManip, data: integer[]) Sets node content IDs
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
---@type VectorModule
vector = {}

---@class VeinMinerUtils
local utils = {}

---@class VienMinerLateUtils
local l_utils = {}

---@class PlayerConfig
---@field miny number
---@field maxy number
---@field last_maxy number|nil
---@type PlayerConfig
local config_data = {}

---@class PlayerConfigManager
---@field data table<string, PlayerConfig>
---@field save_player_config fun(name: string): nil
---@field load_player_config fun(name: string): nil
local p_config = {}

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
---@field set_wielded_item fun(self:ObjectRef, item:ItemStack)
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
---@field get_fov fun(self:ObjectRef): number
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
---@field get_player_control fun(self:ObjectRef): table
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
