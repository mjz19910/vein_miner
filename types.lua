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

---@class ItemStack
---@field get_count fun(self: ItemStack): integer
---@field get_name fun(self: ItemStack): string
---@field take_item fun(self: ItemStack, count: integer): ItemStack
---@field add_item fun(self: ItemStack, stack: ItemStack|string): ItemStack
---@field get_wear fun(self: ItemStack): integer
---@field set_wear fun(self: ItemStack, wear: integer)
---@field get_meta fun(self: ItemStack): MetaDataRef
---@field to_string fun(self: ItemStack): string

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

---@class Chunk
---@field area VoxelArea
---@field start_list Vector[]

---@class VeinMinerConfig
---@field cardinal_dirs Vector[]

---@class VeinMinerGlobal
---@field CFG VeinMinerConfig
---@field MINE_ONLY_CUR_SET string[]
