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
local player = {}

---@class Chunk
---@field area VoxelArea
---@field start_list Vector[]
local chunk = {}

---@class VeinMinerConfig
---@field cardinal_dirs Vector[]
---@field MINE_ONLY_CUR_SET string[]
---@field VEC_DIRS Vector[]
local config = {}

---@class VeinMinerGlobal
---@field CFG VeinMinerConfig
local vein_miner = {}

---@class LuantiCore
---@field get_voxel_manip fun(): VoxelManip
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
